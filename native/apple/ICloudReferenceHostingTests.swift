import CryptoKit
import Foundation

/// Filesystem-only tests. The fake environment never reads an Apple account,
/// resolves an actual iCloud container, or publishes anything to the network.
private final class FakeDrive: ICloudReferenceEnvironment, @unchecked Sendable {
  let root: URL
  private let lock = NSLock()
  private var accountValue: NSString? = "account-a"
  private var uploadedValue = true
  private var publishFailureValue = false
  private var copiesValue = 0
  private var publicationsValue = 0
  private var publicationGate: DispatchSemaphore?
  var supported = true

  init(root: URL) { self.root = root }
  func isSupported(_ configuration: ICloudReferenceHosting.Configuration) -> Bool { supported }
  func identityToken() -> NSObject? { lock.lock(); defer { lock.unlock() }; return accountValue }
  func driveRoot(_ configuration: ICloudReferenceHosting.Configuration) throws -> URL? { root }
  func moveToDrive(_ source: URL, destination: URL) throws {
    try FileManager.default.moveItem(at: source, to: destination)
    lock.lock(); copiesValue += 1; lock.unlock()
  }
  func uploadObservation(_ url: URL) throws -> ICloudReferenceUploadObservation {
    lock.lock(); defer { lock.unlock() }
    return ICloudReferenceUploadObservation(uploaded: uploadedValue, error: nil)
  }
  func publish(_ url: URL) throws -> (url: URL, expiration: Date?) {
    lock.lock(); publicationsValue += 1; let fails = publishFailureValue; let gate = publicationGate; lock.unlock()
    gate?.wait()
    if fails { throw NSError(domain: "Fake", code: 1) }
    return (URL(string: "https://www.icloud.com/attachment/test-only-fixture")!, Date().addingTimeInterval(3600))
  }
  func account(_ value: String?) { lock.lock(); accountValue = value.map { $0 as NSString }; lock.unlock() }
  func uploaded(_ value: Bool) { lock.lock(); uploadedValue = value; lock.unlock() }
  func failPublication(_ value: Bool) { lock.lock(); publishFailureValue = value; lock.unlock() }
  func blockPublication() { lock.lock(); publicationGate = DispatchSemaphore(value: 0); lock.unlock() }
  func unblockPublication() { lock.lock(); let gate = publicationGate; lock.unlock(); gate?.signal() }
  var copies: Int { lock.lock(); defer { lock.unlock() }; return copiesValue }
  var publications: Int { lock.lock(); defer { lock.unlock() }; return publicationsValue }
}

private struct Harness {
  let base: URL
  let journal: URL
  let source: URL
  let drive: FakeDrive
  let service: ICloudReferenceHosting
  let digest: String
  let bytes = Data(repeating: 0x5a, count: 128 * 1024)

  init() throws {
    base = FileManager.default.temporaryDirectory.appendingPathComponent("clawnsole-native-drive-tests-" + UUID().uuidString, isDirectory: true)
    journal = base.appendingPathComponent("journal", isDirectory: true)
    source = base.appendingPathComponent("source.mp4")
    let root = base.appendingPathComponent("fake-drive", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try bytes.write(to: source)
    digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    drive = FakeDrive(root: root)
    service = ICloudReferenceHosting(configuration: .userDrive, journalDirectory: journal, environment: drive)
  }
  func dispose() { try? FileManager.default.removeItem(at: base) }
  func scope() async throws -> String {
    let result = await service.handle(method: "status", arguments: [:])
    try expect(result["state"] as? String == "ready", "fake Drive should be ready")
    guard let scope = result["accountScope"] as? String else { throw TestFailure("scope missing") }
    return scope
  }
  func args(_ id: String, _ scope: String, timeout: Int = 1000) -> [String: Any] {
    ["leaseId": id, "expectedAccountScope": scope, "sourcePath": source.path,
     "filename": "source.mp4", "sha256": digest, "bytes": bytes.count, "timeoutMs": timeout]
  }
  func cloudSource(_ id: String) throws -> URL {
    let raw = try Data(contentsOf: journal.appendingPathComponent("leases/" + id + ".json"))
    let lease = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
    return drive.root.appendingPathComponent("Clawnsole Reference Hosting")
      .appendingPathComponent(lease["directoryId"] as! String).appendingPathComponent(lease["filename"] as! String)
  }
}

private struct TestFailure: Error { let message: String; init(_ message: String) { self.message = message } }
private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
  if try !condition() { throw TestFailure(message) }
}
private func errorCode(_ result: [String: Any]) -> String? { (result["error"] as? [String: Any])?["code"] as? String }
private func hasBearerURL(_ value: Any) -> Bool {
  if let dictionary = value as? [String: Any] {
    return dictionary.keys.contains("publishedUrl") || dictionary.values.contains { hasBearerURL($0) }
  }
  if let array = value as? [Any] { return array.contains { hasBearerURL($0) } }
  return false
}

@main
struct ICloudReferenceHostingTests {
  static func main() async throws {
    try await idempotenceAndCleanup()
    try await accountsAndRecovery()
    try await timeoutResumeAndCancel()
    try await uncertainPublication()
    try await responsiveDuringPublication()
    try await unsafeSources()
    print("iCloud reference hosting: 6 filesystem test groups passed; no cloud/network access.")
  }

  static func idempotenceAndCleanup() async throws {
    let h = try Harness(); defer { h.dispose() }
    let scope = try await h.scope()
    let id = "tm_" + String(repeating: "a", count: 64)
    let args = h.args(id, scope)
    let first = await h.service.handle(method: "prepare", arguments: args)
    try expect(first["state"] as? String == "published", "publication should succeed: \(String(describing: first["error"]))")
    try expect(first["publishedUrl"] != nil, "privileged prepare needs URL")
    let source = try h.cloudSource(id)
    try expect(try Data(contentsOf: source) == h.bytes, "cloud copy should match original")
    let second = await h.service.handle(method: "prepare", arguments: args)
    try expect(second["publishedUrl"] as? String == first["publishedUrl"] as? String, "retry should reuse same URL")
    try expect(h.drive.copies == 1 && h.drive.publications == 1, "retry must not duplicate copy/publication")
    let listing = await h.service.handle(method: "leases", arguments: [:])
    try expect(!hasBearerURL(listing), "lease listing must redact bearer URL")
    let attributes = try FileManager.default.attributesOfItem(atPath: h.journal.appendingPathComponent("leases/" + id + ".json").path)
    try expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "lease must be owner-only")
    let foreign = source.deletingLastPathComponent().appendingPathComponent("keep-user-file.txt")
    try Data("keep".utf8).write(to: foreign)
    let cleanup = await h.service.handle(method: "cleanup", arguments: args)
    try expect(cleanup["sourceCleanup"] as? String == "removedLocally", "source cleanup should complete")
    try expect(cleanup["ownDirectoryRemoved"] as? Bool == false, "nonempty owned folder must remain")
    try expect(FileManager.default.fileExists(atPath: foreign.path), "foreign file must not be removed")
    try expect(!FileManager.default.fileExists(atPath: source.path), "owned source must be removed")
    try expect(cleanup["publishedUrlExpiresAt"] != nil && !hasBearerURL(cleanup), "cleanup keeps expiry but erases URL")
    try expect(cleanup["urlRevocation"] as? String == "notGuaranteed", "cleanup cannot promise revocation")
  }

  static func accountsAndRecovery() async throws {
    let h = try Harness(); defer { h.dispose() }
    let scope = try await h.scope(); let id = UUID().uuidString
    let args = h.args(id, scope)
    _ = await h.service.handle(method: "prepare", arguments: args)
    let reopened = ICloudReferenceHosting(configuration: .userDrive, journalDirectory: h.journal, environment: h.drive)
    let recovered = await reopened.handle(method: "lease", arguments: args)
    try expect(recovered["publishedUrl"] != nil, "relaunch should recover secure URL")
    h.drive.account("account-b")
    let wrong = await reopened.handle(method: "cleanup", arguments: args)
    try expect(errorCode(wrong) == "accountChanged", "wrong account must not clean source")
    let secondScope = await reopened.handle(method: "status", arguments: [:])["accountScope"] as? String
    try expect(secondScope != nil && secondScope != scope, "different account needs different scope")
    let listing = await reopened.handle(method: "leases", arguments: [:])
    try expect(!hasBearerURL(listing), "wrong-account listing must not leak URL")
    h.drive.account("account-a")
    let originalScope = await reopened.handle(method: "status", arguments: [:])["accountScope"] as? String
    try expect(originalScope == scope, "returning account must regain stable scope")
    let cleaned = await reopened.handle(method: "cleanup", arguments: args)
    try expect(cleaned["sourceCleanup"] as? String == "removedLocally", "original account should clean source")
    h.drive.account(nil)
    let noAccount = await reopened.handle(method: "status", arguments: [:])
    try expect(noAccount["state"] as? String == "noAccount", "unavailable identity should have actionable status")
  }

  static func timeoutResumeAndCancel() async throws {
    let h = try Harness(); defer { h.dispose() }
    let scope = try await h.scope(); let id = UUID().uuidString
    h.drive.uploaded(false)
    let args = h.args(id, scope)
    let timed = await h.service.handle(method: "prepare", arguments: args)
    try expect(errorCode(timed) == "timeout", "upload should have bounded wait")
    h.drive.uploaded(true)
    let resumed = await h.service.handle(method: "prepare", arguments: args)
    try expect(resumed["state"] as? String == "published" && h.drive.copies == 1, "retry should resume owned copy")
    _ = await h.service.handle(method: "cleanup", arguments: args)
    h.drive.uploaded(false)
    let cancelId = UUID().uuidString; let cancelArgs = h.args(cancelId, scope, timeout: 10000)
    let task = Task { await h.service.handle(method: "prepare", arguments: cancelArgs) }
    try await Task.sleep(nanoseconds: 150_000_000)
    let cancel = await h.service.handle(method: "cancel", arguments: ["leaseId": cancelId])
    try expect(cancel["cancellationRequested"] as? Bool == true, "active request should accept cancel")
    let cancelled = await task.value
    try expect(errorCode(cancelled) == "cancelled", "cancel should interrupt upload polling")
    let cleaned = await h.service.handle(method: "cleanup", arguments: cancelArgs)
    try expect(cleaned["sourceCleanup"] as? String == "removedLocally", "cancelled source should be recoverably cleaned")
  }

  static func uncertainPublication() async throws {
    let h = try Harness(); defer { h.dispose() }
    let scope = try await h.scope(); let id = UUID().uuidString; let args = h.args(id, scope)
    h.drive.failPublication(true)
    _ = await h.service.handle(method: "prepare", arguments: args)
    h.drive.failPublication(false)
    let recovered = ICloudReferenceHosting(configuration: .userDrive, journalDirectory: h.journal, environment: h.drive)
    let retry = await recovered.handle(method: "prepare", arguments: args)
    try expect(errorCode(retry) == "publicationUncertain", "interrupted publication must not create another snapshot")
    try expect(h.drive.publications == 1, "publication cannot be repeated when outcome is uncertain")
    let cleaned = await recovered.handle(method: "cleanup", arguments: args)
    try expect(cleaned["sourceCleanup"] as? String == "removedLocally", "uncertain publication source should be cleaned")
  }

  static func responsiveDuringPublication() async throws {
    let h = try Harness(); defer { h.dispose() }
    let scope = try await h.scope(); let id = UUID().uuidString
    let args = h.args(id, scope, timeout: 10000)
    h.drive.blockPublication()
    defer { h.drive.unblockPublication() }
    let publication = Task { await h.service.handle(method: "prepare", arguments: args) }
    while h.drive.publications == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
    // Bound the regression itself: a blocked actor must fail a timing assertion,
    // not wedge CI forever while the fake publication waits for its release.
    let watchdog = Task.detached {
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      h.drive.unblockPublication()
    }
    defer { watchdog.cancel() }
    let began = Date()
    let status = await h.service.handle(method: "status", arguments: [:])
    try expect(status["state"] as? String == "ready", "status should remain available during publication")
    try expect(Date().timeIntervalSince(began) < 1.0, "publication must not block the service actor")
    let busyCleanup = await h.service.handle(method: "cleanup", arguments: args)
    try expect(errorCode(busyCleanup) == "busy", "cleanup cannot race publication")
    let cancelled = await h.service.handle(method: "cancel", arguments: ["leaseId": id])
    try expect(cancelled["cancellationRequested"] as? Bool == true, "cancel should reach blocked publication")
    h.drive.unblockPublication()
    let result = await publication.value
    try expect(errorCode(result) == "cancelled", "completed publication must honor queued cancellation")
    let receipt = await h.service.handle(method: "lease", arguments: args)
    try expect(receipt["state"] as? String == "published" && receipt["expiresAt"] != nil,
               "publication outcome must be journaled before cancellation is returned")
    let cleaned = await h.service.handle(method: "cleanup", arguments: args)
    try expect(cleaned["sourceCleanup"] as? String == "removedLocally", "cancelled publication remains cleanable")
  }

  static func unsafeSources() async throws {
    let h = try Harness(); defer { h.dispose() }
    let scope = try await h.scope()
    let invalid = await h.service.handle(method: "prepare", arguments: h.args("../escape", scope))
    try expect(errorCode(invalid) == "invalidArguments", "path-like lease ID must be rejected")
    let link = h.base.appendingPathComponent("linked.mp4")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: h.source)
    let id = UUID().uuidString; var args = h.args(id, scope); args["sourcePath"] = link.path
    let rejected = await h.service.handle(method: "prepare", arguments: args)
    try expect(errorCode(rejected) == "unsafePath", "symlinked input must be rejected")
    try expect(h.drive.copies == 0, "symlinked input must not enter Drive")
    _ = await h.service.handle(method: "cleanup", arguments: args)
    let publishedId = UUID().uuidString; let publishedArgs = h.args(publishedId, scope)
    _ = await h.service.handle(method: "prepare", arguments: publishedArgs)
    let owned = try h.cloudSource(publishedId)
    try FileManager.default.removeItem(at: owned)
    try FileManager.default.createSymbolicLink(at: owned, withDestinationURL: h.source)
    let unsafeCleanup = await h.service.handle(method: "cleanup", arguments: publishedArgs)
    try expect(errorCode(unsafeCleanup) == "unsafePath", "cleanup must reject replaced source symlink")
    try expect(FileManager.default.fileExists(atPath: h.source.path), "cleanup must never delete user input")
  }
}
