import CryptoKit
import Foundation
import Darwin

/// User-owned iCloud Drive publication. This service never uses CloudKit.
///
/// Published URLs are bearer capabilities: only `prepare` and `lease` return
/// them to the privileged caller. Do not log requests, responses, or journals,
/// and never put these URLs in generation history or renderer storage.
actor ICloudReferenceHosting {
  enum Configuration: Equatable {
    case appContainer(String)
    case userDrive
  }

  struct Failure: Error {
    let code: String
    let message: String
    var retryable = false
  }

  struct Lease: Codable {
    var version = 1
    let leaseId: String
    let directoryId: String
    let accountScope: String
    let filename: String
    let sha256: String
    let bytes: Int64
    let createdAt: Date
    var updatedAt: Date
    var state: String
    var publishedUrl: String?
    var expiresAt: Date?
    var sourceCleanedAt: Date?
  }

  private struct Account: Codable {
    let version: Int
    let scope: String
    let token: Data
  }

  private let configuration: Configuration
  private let journalDirectory: URL
  private let environment: ICloudReferenceEnvironment
  private let fm = FileManager.default
  private var active = Set<String>()
  private var cancelled = Set<String>()

  init(configuration: Configuration, journalDirectory: URL) {
    self.configuration = configuration
    self.journalDirectory = journalDirectory.standardizedFileURL
    self.environment = FoundationICloudReferenceEnvironment()
  }

  // Dependency injection is internal, used by the filesystem recovery tests.
  init(configuration: Configuration, journalDirectory: URL,
       environment: ICloudReferenceEnvironment) {
    self.configuration = configuration
    self.journalDirectory = journalDirectory.standardizedFileURL
    self.environment = environment
  }

  /// Run from a detached/background task. Foundation container discovery and
  /// publication are synchronous OS APIs without a cancellable timeout. Copy
  /// work and upload polling have cooperative cancellation and a deadline.
  func handle(method: String, arguments: [String: Any]) async -> [String: Any] {
    do {
      switch method {
      case "status": return try status()
      case "prepare": return try await prepare(arguments)
      case "lease":
        let lease = try load(try identifier(arguments))
        _ = try checkedAccount(expected: try expectedScope(arguments))
        try requireScope(lease.accountScope, try expectedScope(arguments))
        return payload(lease, includeURL: true)
      case "leases": return try leases()
      case "cleanup": return try await cleanup(arguments)
      case "cancel":
        let id = try identifier(arguments)
        let wasActive = active.contains(id)
        if wasActive { cancelled.insert(id) }
        return ["ok": true, "leaseId": id, "cancellationRequested": wasActive,
                "sourceCleanup": "notPerformed", "urlRevocation": "notGuaranteed"]
      default: throw Failure(code: "unsupportedMethod", message: "Unsupported iCloud Drive operation.")
      }
    } catch let error as Failure {
      return ["ok": false, "error": ["code": error.code, "message": error.message,
                                      "retryable": error.retryable]]
    } catch is CancellationError {
      return ["ok": false, "error": ["code": "cancelled", "message": "iCloud Drive preparation was cancelled.", "retryable": true]]
    } catch {
      // Foundation error descriptions can embed local paths or bearer URLs.
      // Expose a stable error only; never forward localizedDescription/userInfo.
      return ["ok": false, "error": ["code": "unavailable", "message": "iCloud Drive could not complete this operation. Try again when iCloud Drive is available.", "retryable": true]]
    }
  }

  private func status() throws -> [String: Any] {
    guard environment.isSupported(configuration) else {
      return ["ok": true, "supported": false, "state": "unsupported",
              "message": "iCloud Drive reference hosting is unavailable on this platform."]
    }
    guard environment.identityToken() != nil else {
      // Foundation provides no supported API that reliably distinguishes a
      // signed-out account from iCloud Drive being disabled in every setup.
      return ["ok": true, "supported": true, "state": "noAccount",
              "message": "Sign in to iCloud and enable iCloud Drive for Clawnsole in Settings.",
              "accountStateDetail": "accountOrDriveUnavailable"]
    }
    do {
      let scope = try checkedAccount(expected: nil)
      guard let root = try environment.driveRoot(configuration), isDirectory(root) else {
        return ["ok": true, "supported": true, "state": "driveUnavailable",
                "accountScope": scope,
                "message": "iCloud Drive is unavailable to Clawnsole. Enable iCloud Drive for this app and try again."]
      }
      return ["ok": true, "supported": true, "state": "ready", "accountScope": scope,
              "storageOwner": "user", "message": "References use your iCloud Drive storage.",
              "urlRevocation": "notGuaranteed"]
    } catch {
      return ["ok": true, "supported": true, "state": "unavailable",
              "message": "iCloud Drive is temporarily unavailable. Try again shortly."]
    }
  }

  private func prepare(_ arguments: [String: Any]) async throws -> [String: Any] {
    let id = try identifier(arguments)
    let expected = try expectedScope(arguments)
    guard !active.contains(id) else { throw busy() }
    active.insert(id)
    cancelled.remove(id)
    defer { active.remove(id); cancelled.remove(id) }
    let timeout = min(max((arguments["timeoutMs"] as? NSNumber)?.doubleValue ?? 180_000, 1000), 900_000) / 1000
    let deadline = Date().addingTimeInterval(timeout)
    let scope = try checkedAccount(expected: expected)
    let root = try storageRoot()
    guard let digest = arguments["sha256"] as? String,
          digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
          let count = arguments["bytes"] as? NSNumber, count.int64Value > 0,
          let sourcePath = arguments["sourcePath"] as? String,
          sourcePath.hasPrefix("/"), !sourcePath.contains("\0") else {
      throw invalid()
    }
    let bytes = count.int64Value
    let source = URL(fileURLWithPath: sourcePath).standardizedFileURL
    let filename = Self.assetFilename(arguments["filename"] as? String ?? "asset")
    var lease: Lease
    if let existing = try optionalLoad(id) {
      try requireScope(existing.accountScope, scope)
      guard existing.sha256 == digest, existing.bytes == bytes else {
        throw Failure(code: "leaseConflict", message: "This reference lease belongs to a different asset.")
      }
      lease = existing
      if lease.state == "published", let expiration = lease.expiresAt, expiration > Date() {
        try checkOperation(id, expected: expected, deadline: deadline)
        return payload(lease, includeURL: true)
      }
      if lease.state == "published" {
        throw Failure(code: "expired", message: "This reference link expired. Clean up this lease and create a new one.")
      }
      if lease.state == "publishing" {
        throw Failure(code: "publicationUncertain", message: "Publication was interrupted. Clean up this lease before preparing a new reference.")
      }
      if lease.state == "cleaned" {
        throw Failure(code: "leaseClosed", message: "This reference lease has already been cleaned up.")
      }
    } else {
      lease = Lease(leaseId: id, directoryId: UUID().uuidString.lowercased(),
                    accountScope: scope, filename: filename, sha256: digest, bytes: bytes,
                    createdAt: Date(), updatedAt: Date(), state: "preparing")
      // Intent is durable before creating any cloud source or local staging file.
      try save(lease)
    }
    let target = try destination(lease, root: root)
    do {
      try checkOperation(id, expected: expected, deadline: deadline)
      if exists(target) {
        try verifyFile(target, lease: lease)
      } else {
        let folder = target.deletingLastPathComponent()
        try createOwnedDirectory(folder, beneath: root)
        let stage = try stagingURL(lease)
        if exists(stage) {
          // A crash may leave a partial local copy. It is in our private local
          // journal, never a user's source, and is replaced only as a regular file.
          try requireRegularFile(stage)
          try fm.removeItem(at: stage)
        }
        try await copySource(source, to: stage, lease: lease, expected: expected, deadline: deadline)
        try checkOperation(id, expected: expected, deadline: deadline)
        lease.state = "uploading"; try save(lease)
        try environment.moveToDrive(stage, destination: target)
      }
      lease.state = "uploading"; try save(lease)
      let pollingStarted = Date()
      while true {
        try checkOperation(id, expected: expected, deadline: deadline)
        let observation = try environment.uploadObservation(target)
        if observation.uploaded {
          break
        }
        if let failure = observation.error {
          // iCloud can briefly report connection unavailability while a fresh
          // copy is being registered. Always query fresh resource values again.
          let initialTransient = failure.domain == NSCocoaErrorDomain && failure.code == 4355
            && Date().timeIntervalSince(pollingStarted) < 45
          if !initialTransient {
            throw Failure(code: "uploadFailed", message: "iCloud Drive could not upload this reference. Check your connection and available iCloud storage, then retry.", retryable: true)
          }
        }
        try await Task.sleep(nanoseconds: 500_000_000)
      }
      try checkOperation(id, expected: expected, deadline: deadline)
      try verifyFile(target, lease: lease)
      lease.state = "publishing"; try save(lease)
      // Foundation has no cancellation API for publication. Keep that blocking
      // call off this actor so readiness and cancellation requests still run.
      // `active` keeps cleanup/retry of this lease excluded until it returns.
      let publisher = environment
      let publication = try await Task.detached(priority: .utility) {
        try publisher.publish(target)
      }.value
      // Record the capability immediately, even if the account changed or the
      // deadline elapsed during the synchronous OS call. Do not return it then.
      guard Self.validPublicationURL(publication.url), let expiration = publication.expiration,
            expiration > Date() else {
        throw Failure(code: "invalidPublication", message: "iCloud Drive did not return a valid expiring reference link.")
      }
      lease.publishedUrl = publication.url.absoluteString
      lease.expiresAt = expiration
      lease.state = "published"; try save(lease)
      try checkOperation(id, expected: expected, deadline: deadline)
      return payload(lease, includeURL: true)
    } catch {
      // Preserve phase and owned path so retry or cleanup can recover after
      // timeout/cancellation/crash. Never discard a lease with a possible URL.
      try? save(lease)
      throw error
    }
  }

  private func cleanup(_ arguments: [String: Any]) async throws -> [String: Any] {
    let id = try identifier(arguments)
    guard !active.contains(id) else { throw busy() }
    active.insert(id)
    defer { active.remove(id) }
    let expected = try expectedScope(arguments)
    _ = try checkedAccount(expected: expected)
    var lease = try load(id)
    try requireScope(lease.accountScope, expected)
    if lease.state == "cleaned" { return payload(lease, includeURL: false) }
    let target = try destination(lease, root: storageRoot())
    if exists(target) {
      try verifyFile(target, lease: lease)
      _ = try checkedAccount(expected: expected)
      var coordinatorError: NSError?
      var deletionError: Error?
      NSFileCoordinator().coordinate(writingItemAt: target, options: .forDeleting,
                                      error: &coordinatorError) { coordinated in
        do {
          guard coordinated.standardizedFileURL == target.standardizedFileURL else { throw invalid() }
          try verifyFile(coordinated, lease: lease)
          _ = try checkedAccount(expected: expected)
          try fm.removeItem(at: coordinated)
        } catch { deletionError = error }
      }
      if let coordinatorError { throw coordinatorError }
      if let deletionError { throw deletionError }
    }
    _ = try checkedAccount(expected: expected)
    let folder = target.deletingLastPathComponent()
    // Never recursively delete a cloud folder. rmdir leaves unexpected files.
    var folderRemoved = !exists(folder)
    if !folderRemoved {
      try requireOwnedDirectory(folder)
      folderRemoved = Darwin.rmdir(folder.path) == 0
    }
    let stage = try stagingURL(lease)
    if exists(stage) {
      try requireRegularFile(stage)
      try fm.removeItem(at: stage)
    }
    lease.state = "cleaned"
    lease.sourceCleanedAt = Date()
    // Keep expiry metadata, erase the bearer URL when the caller releases it.
    lease.publishedUrl = nil
    try save(lease)
    var result = payload(lease, includeURL: false)
    result["ownDirectoryRemoved"] = folderRemoved
    result["remoteDeletionConfirmed"] = false
    return result
  }

  private func leases() throws -> [String: Any] {
    try ensureJournal()
    let scope = try? checkedAccount(expected: nil)
    let directory = journalDirectory.appendingPathComponent("leases", isDirectory: true)
    let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    var values: [[String: Any]] = []
    for file in files where file.pathExtension == "json" {
      let id = file.deletingPathExtension().lastPathComponent
      guard Self.validIdentifier(id) else { continue }
      let lease = try load(id)
      var value = payload(lease, includeURL: false)
      value["accountMatches"] = scope == lease.accountScope
      value["operationActive"] = active.contains(id)
      values.append(value)
    }
    return ["ok": true, "leases": values]
  }

  private func payload(_ lease: Lease, includeURL: Bool) -> [String: Any] {
    var result: [String: Any] = [
      "ok": true, "leaseId": lease.leaseId, "state": lease.state,
      "accountScope": lease.accountScope, "sha256": lease.sha256, "bytes": lease.bytes,
      "createdAt": Self.iso(lease.createdAt), "updatedAt": Self.iso(lease.updatedAt),
      "sourceCleanup": lease.sourceCleanedAt == nil ? "pending" : "removedLocally",
      "urlRevocation": "notGuaranteed", "storageOwner": "user",
    ]
    if let expiration = lease.expiresAt {
      result["expiresAt"] = Self.iso(expiration)
      result["publishedUrlExpiresAt"] = Self.iso(expiration)
      result["urlExpired"] = expiration <= Date()
    }
    if let cleaned = lease.sourceCleanedAt { result["sourceCleanedAt"] = Self.iso(cleaned) }
    if includeURL, lease.state == "published", let url = lease.publishedUrl,
       let expiration = lease.expiresAt, expiration > Date() {
      result["publishedUrl"] = url
    }
    return result
  }

  private func copySource(_ source: URL, to stage: URL, lease: Lease,
                          expected: String, deadline: Date) async throws {
    try requireRegularFile(source)
    let sourceFD = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW)
    guard sourceFD >= 0 else { throw Failure(code: "sourceUnavailable", message: "The reference file cannot be read.") }
    let input = FileHandle(fileDescriptor: sourceFD, closeOnDealloc: true)
    defer { try? input.close() }
    var sourceInfo = stat()
    guard fstat(sourceFD, &sourceInfo) == 0, sourceInfo.st_mode & S_IFMT == S_IFREG,
          sourceInfo.st_size == lease.bytes else {
      throw Failure(code: "sourceChanged", message: "The reference file changed. Select it again.")
    }
    let stageFD = Darwin.open(stage.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
    guard stageFD >= 0 else { throw Failure(code: "stagingUnavailable", message: "Clawnsole could not stage this reference.", retryable: true) }
    let output = FileHandle(fileDescriptor: stageFD, closeOnDealloc: true)
    defer { try? output.close() }
    var hash = SHA256()
    var copied: Int64 = 0
    while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
      try checkOperation(lease.leaseId, expected: expected, deadline: deadline)
      try output.write(contentsOf: data)
      hash.update(data: data)
      copied += Int64(data.count)
      if copied > lease.bytes { throw Failure(code: "sourceChanged", message: "The reference file changed. Select it again.") }
      await Task.yield()
    }
    try output.synchronize()
    guard copied == lease.bytes, Self.hex(hash.finalize()) == lease.sha256 else {
      throw Failure(code: "sourceChanged", message: "The reference file changed. Select it again.")
    }
  }

  private func checkOperation(_ id: String, expected: String, deadline: Date) throws {
    if cancelled.contains(id) || Task.isCancelled { throw Failure(code: "cancelled", message: "iCloud Drive preparation was cancelled.", retryable: true) }
    if Date() >= deadline { throw Failure(code: "timeout", message: "iCloud Drive is still preparing the reference. Retry to resume this upload.", retryable: true) }
    _ = try checkedAccount(expected: expected)
  }

  private func checkedAccount(expected: String?) throws -> String {
    guard environment.isSupported(configuration) else { throw Failure(code: "unsupported", message: "iCloud Drive reference hosting is unavailable on this platform.") }
    guard let token = environment.identityToken() else {
      throw Failure(code: "noAccount", message: "Sign in to iCloud and enable iCloud Drive for Clawnsole in Settings.", retryable: true)
    }
    try ensureJournal()
    let path = journalDirectory.appendingPathComponent("accounts.json")
    var identities: [Account] = []
    if exists(path) {
      try requireRegularFile(path)
      identities = try JSONDecoder().decode([Account].self, from: Data(contentsOf: path))
    }
    for identity in identities {
      // The opaque token's private Foundation class is not an application API.
      // Decode only our private, app-written archive and compare with isEqual,
      // as Apple recommends; never assume serialized bytes are a stable ID.
      let decoder = try NSKeyedUnarchiver(forReadingFrom: identity.token)
      decoder.requiresSecureCoding = false
      let previousToken = decoder.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
      decoder.finishDecoding()
      if let previousToken, token.isEqual(previousToken) {
        if let expected { try requireScope(identity.scope, expected) }
        return identity.scope
      }
    }
    // Never silently bind an in-flight operation to a different Apple account.
    if expected != nil { throw Failure(code: "accountChanged", message: "Your iCloud account changed. Refresh iCloud Drive status before continuing.") }
    let scope = Self.hex(SHA256.hash(data: Data(UUID().uuidString.utf8)))
    let encoded = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
    identities.append(Account(version: 1, scope: scope, token: encoded))
    try writePrivate(JSONEncoder().encode(identities), to: path)
    return scope
  }

  private func storageRoot() throws -> URL {
    guard let base = try environment.driveRoot(configuration), isDirectory(base) else {
      throw Failure(code: "driveUnavailable", message: "Enable iCloud Drive for Clawnsole and try again.", retryable: true)
    }
    try requireOwnedDirectory(base)
    let root = base.appendingPathComponent("Clawnsole Reference Hosting", isDirectory: true)
    if !exists(root) {
      try fm.createDirectory(at: root, withIntermediateDirectories: false)
    }
    try requireOwnedDirectory(root)
    return root
  }

  private func destination(_ lease: Lease, root: URL) throws -> URL {
    guard UUID(uuidString: lease.directoryId) != nil,
          Self.validIdentifier(lease.leaseId), lease.filename == Self.assetFilename(lease.filename) else { throw invalid() }
    let folder = root.appendingPathComponent(lease.directoryId, isDirectory: true)
    if exists(folder) { try requireOwnedDirectory(folder) }
    return folder.appendingPathComponent(lease.filename)
  }

  private func stagingURL(_ lease: Lease) throws -> URL {
    try ensureJournal()
    guard UUID(uuidString: lease.directoryId) != nil else { throw invalid() }
    return journalDirectory.appendingPathComponent("staging", isDirectory: true)
      .appendingPathComponent(lease.directoryId + ".partial")
  }

  private func createOwnedDirectory(_ url: URL, beneath root: URL) throws {
    try requireOwnedDirectory(root)
    guard url.deletingLastPathComponent() == root,
          UUID(uuidString: url.lastPathComponent) != nil else { throw invalid() }
    if !exists(url) { try fm.createDirectory(at: url, withIntermediateDirectories: false) }
    try requireOwnedDirectory(url)
  }

  private func ensureJournal() throws {
    try fm.createDirectory(at: journalDirectory, withIntermediateDirectories: true,
                           attributes: [.posixPermissions: 0o700])
    try requireOwnedDirectory(journalDirectory)
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: journalDirectory.path)
    for name in ["leases", "staging"] {
      let child = journalDirectory.appendingPathComponent(name, isDirectory: true)
      if !exists(child) {
        try fm.createDirectory(at: child, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
      }
      try requireOwnedDirectory(child)
    }
    var url = journalDirectory
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    try url.setResourceValues(values)
    #if os(iOS)
    try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: journalDirectory.path)
    #endif
  }

  private func save(_ value: Lease) throws {
    try ensureJournal()
    var lease = value; lease.updatedAt = Date()
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    try writePrivate(encoder.encode(lease), to: leaseURL(lease.leaseId))
  }

  private func writePrivate(_ data: Data, to url: URL) throws {
    if exists(url) { try requireRegularFile(url) }
    try data.write(to: url, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    let handle = try FileHandle(forWritingTo: url)
    try handle.synchronize()
    try handle.close()
    #if os(iOS)
    try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
    #endif
  }

  private func leaseURL(_ id: String) throws -> URL {
    guard Self.validIdentifier(id) else { throw invalid() }
    return journalDirectory.appendingPathComponent("leases", isDirectory: true).appendingPathComponent(id + ".json")
  }

  private func optionalLoad(_ id: String) throws -> Lease? {
    try ensureJournal()
    let path = try leaseURL(id)
    guard exists(path) else { return nil }
    try requireRegularFile(path)
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let lease = try decoder.decode(Lease.self, from: Data(contentsOf: path))
    guard lease.version == 1, lease.leaseId == id, UUID(uuidString: lease.directoryId) != nil else { throw invalid() }
    return lease
  }

  private func load(_ id: String) throws -> Lease {
    guard let lease = try optionalLoad(id) else { throw Failure(code: "leaseNotFound", message: "This iCloud Drive reference lease was not found.") }
    return lease
  }

  private func verifyFile(_ url: URL, lease: Lease) throws {
    try requireRegularFile(url)
    let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else { throw Failure(code: "unsafePath", message: "The owned reference copy cannot be read safely.") }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? handle.close() }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw invalid() }
    var hash = SHA256(); var count: Int64 = 0
    while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
      hash.update(data: data); count += Int64(data.count)
    }
    guard count == lease.bytes, Self.hex(hash.finalize()) == lease.sha256 else {
      throw Failure(code: "sourceChanged", message: "The owned iCloud reference copy changed. Clawnsole left it untouched.")
    }
  }

  private func requireRegularFile(_ url: URL) throws {
    var info = stat()
    guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
      throw Failure(code: "unsafePath", message: "The reference path is not an owned regular file.")
    }
  }

  private func requireOwnedDirectory(_ url: URL) throws {
    var info = stat()
    guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
      throw Failure(code: "unsafePath", message: "The reference storage folder is unavailable or unsafe.")
    }
  }

  private func exists(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) == 0
  }

  private func isDirectory(_ url: URL) -> Bool {
    var directory: ObjCBool = false
    return fm.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
  }

  private func identifier(_ arguments: [String: Any]) throws -> String {
    guard let id = arguments["leaseId"] as? String, Self.validIdentifier(id) else { throw invalid() }
    return id
  }

  private func expectedScope(_ arguments: [String: Any]) throws -> String {
    guard let scope = arguments["expectedAccountScope"] as? String,
          scope.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw invalid() }
    return scope
  }

  private func requireScope(_ actual: String, _ expected: String) throws {
    guard actual == expected else { throw Failure(code: "accountChanged", message: "This reference belongs to a different iCloud account. Switch back to that account to access or clean it up.") }
  }

  private func invalid() -> Failure { Failure(code: "invalidArguments", message: "The iCloud Drive reference request is invalid.") }
  private func busy() -> Failure { Failure(code: "busy", message: "This reference is still being prepared. Cancel or wait before retrying.", retryable: true) }

  static func validIdentifier(_ value: String) -> Bool {
    UUID(uuidString: value) != nil || value.range(of: "^tm_[a-f0-9]{64}$", options: .regularExpression) != nil
  }

  static func assetFilename(_ value: String) -> String {
    let ext = (value as NSString).pathExtension.lowercased()
    guard ext.range(of: "^[a-z0-9]{1,10}$", options: .regularExpression) != nil else { return "asset.bin" }
    return "asset." + ext
  }

  static func validPublicationURL(_ url: URL) -> Bool {
    guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
          let host = url.host?.lowercased() else { return false }
    return host == "icloud.com" || host.hasSuffix(".icloud.com") || host.hasSuffix(".icloud-content.com")
  }

  private static func hex<S: Sequence>(_ digest: S) -> String where S.Element == UInt8 {
    digest.map { String(format: "%02x", $0) }.joined()
  }
  private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}

struct ICloudReferenceUploadObservation {
  let uploaded: Bool
  let error: NSError?
}

protocol ICloudReferenceEnvironment: Sendable {
  func isSupported(_ configuration: ICloudReferenceHosting.Configuration) -> Bool
  func identityToken() -> NSObject?
  func driveRoot(_ configuration: ICloudReferenceHosting.Configuration) throws -> URL?
  func moveToDrive(_ source: URL, destination: URL) throws
  func uploadObservation(_ url: URL) throws -> ICloudReferenceUploadObservation
  func publish(_ url: URL) throws -> (url: URL, expiration: Date?)
}

struct FoundationICloudReferenceEnvironment: ICloudReferenceEnvironment {
  // A fresh manager per operation avoids sharing a non-Sendable instance
  // between actor-isolated status work and the detached publication worker.
  private var fm: FileManager { FileManager() }

  func isSupported(_ configuration: ICloudReferenceHosting.Configuration) -> Bool {
    #if os(iOS)
    if case .appContainer = configuration { return true }
    return false
    #elseif os(macOS)
    return true
    #else
    return false
    #endif
  }

  func identityToken() -> NSObject? { fm.ubiquityIdentityToken as? NSObject }

  func driveRoot(_ configuration: ICloudReferenceHosting.Configuration) throws -> URL? {
    switch configuration {
    case .appContainer(let identifier):
      guard identifier.hasPrefix("iCloud."),
            let base = fm.url(forUbiquityContainerIdentifier: identifier) else { return nil }
      let documents = base.appendingPathComponent("Documents", isDirectory: true)
      if !fm.fileExists(atPath: documents.path) {
        try fm.createDirectory(at: documents, withIntermediateDirectories: false)
      }
      return documents
    case .userDrive:
      #if os(macOS)
      // Unsandboxed Developer ID Electron helper. This location was verified in
      // the POC; it needs no app container and consumes the user's Drive quota.
      // It is not a public FileManager container-discovery API. If unavailable,
      // fail visibly; never guess another folder or scan personal Drive files.
      let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
      var directory: ObjCBool = false
      return fm.fileExists(atPath: root.path, isDirectory: &directory) && directory.boolValue ? root : nil
      #else
      return nil
      #endif
    }
  }

  func moveToDrive(_ source: URL, destination: URL) throws {
    try fm.setUbiquitous(true, itemAt: source, destinationURL: destination)
  }

  func uploadObservation(_ url: URL) throws -> ICloudReferenceUploadObservation {
    var fresh = url
    fresh.removeAllCachedResourceValues()
    let values = try fresh.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey])
    return ICloudReferenceUploadObservation(uploaded: values.isUbiquitousItem == true && values.ubiquitousItemIsUploaded == true,
                                           error: values.ubiquitousItemUploadingError)
  }

  func publish(_ url: URL) throws -> (url: URL, expiration: Date?) {
    var expiration: NSDate?
    let published = try fm.url(forPublishingUbiquitousItemAt: url, expiration: &expiration)
    return (published, expiration as Date?)
  }
}
