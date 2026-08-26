import Flutter
import UIKit

/// Downloads generation results through a background URLSession so the OS
/// completes the transfer while the app is suspended — or even after it was
/// terminated in the background — and retains the finished file until Dart
/// imports it into the asset store.
///
/// Everything here runs on the main thread: the method-channel handler, the
/// session delegate (its delegate queue is the main OperationQueue), and the
/// UIKit lifecycle callbacks, so the mutable state needs no locking.
final class BackgroundDeliveryPlugin: NSObject, URLSessionDownloadDelegate {
  static let sessionIdentifier = "ai.clawnsole.result-downloads"
  private static let manifestKey = "ai.clawnsole.pendingResultDownloads"

  private var session: URLSession?
  private var waiters: [String: [FlutterResult]] = [:]
  // Failures key by task identifier and waiter attribution goes through
  // activeTasks so a superseded transfer's outcome — for example a stale
  // pre-relaunch task holding an expired link — is never attributed to the
  // current transfer of the same generation.
  private var failures: [Int: FlutterError] = [:]
  private var activeTasks: [String: Int] = [:]
  private var backgroundCompletionHandlers: [() -> Void] = []

  func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.clawnsole/background_delivery",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "download": self.download(call, result)
      case "pendingResultIds": result(Array(self.manifest.keys))
      case "pendingResult": self.pendingResult(call, result)
      case "completeResult": self.completeResult(call, result)
      default: result(FlutterMethodNotImplemented)
      }
    }
    // Recreating the session with its stable identifier reattaches this
    // delegate to transfers a previous process left in flight.
    _ = ensureSession()
  }

  /// Called by the AppDelegate when the system relaunched the app for this
  /// session's finished transfers.
  func handleSessionEvents(completionHandler: @escaping () -> Void) {
    backgroundCompletionHandlers.append(completionHandler)
    _ = ensureSession()
  }

  private func ensureSession() -> URLSession {
    if let session { return session }
    let configuration = URLSessionConfiguration.background(
      withIdentifier: Self.sessionIdentifier
    )
    // Background sessions do not honor the per-request timeout on device —
    // nsurlsessiond retries transient failures on its own — so the resource
    // timeout is the only real bound on a dead transfer. Thirty minutes is
    // generous for the largest provider film on a slow connection while
    // keeping a wedged link from pinning its generation for hours.
    configuration.timeoutIntervalForRequest = 60
    configuration.timeoutIntervalForResource = 30 * 60
    configuration.isDiscretionary = false
    configuration.sessionSendsLaunchEvents = true
    let session = URLSession(
      configuration: configuration,
      delegate: self,
      delegateQueue: OperationQueue.main
    )
    self.session = session
    return session
  }

  // MARK: - Channel handlers

  private func download(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    guard
      let id = sanitizedId(arguments?["id"]),
      let urlString = arguments?["url"] as? String,
      let url = URL(string: urlString),
      url.scheme == "https"
    else {
      result(FlutterError(
        code: "invalid",
        message: "The background download request is invalid.",
        details: nil
      ))
      return
    }
    if let payload = retainedPayload(for: id) {
      result(payload)
      return
    }
    waiters[id, default: []].append(result)
    let session = ensureSession()
    session.getAllTasks { [weak self] tasks in
      DispatchQueue.main.async {
        guard let self else { return }
        // The waiter may already have been resolved by a completing task.
        guard self.waiters[id] != nil else { return }
        let inFlight = tasks.first { task in
          task.taskDescription == id
            && (task.state == .running || task.state == .suspended)
        }
        if let inFlight, inFlight.originalRequest?.url == url {
          self.activeTasks[id] = inFlight.taskIdentifier
          return
        }
        // A leftover transfer holding a different — likely expired — link
        // must not have its outcome bound to this fresh one.
        inFlight?.cancel()
        let task = session.downloadTask(with: url)
        task.taskDescription = id
        self.activeTasks[id] = task.taskIdentifier
        task.resume()
      }
    }
  }

  private func pendingResult(_ call: FlutterMethodCall, _ result: FlutterResult) {
    guard let id = sanitizedId((call.arguments as? [String: Any])?["id"]) else {
      result(nil)
      return
    }
    result(retainedPayload(for: id))
  }

  private func completeResult(_ call: FlutterMethodCall, _ result: FlutterResult) {
    if let id = sanitizedId((call.arguments as? [String: Any])?["id"]) {
      var entries = manifest
      entries.removeValue(forKey: id)
      manifest = entries
      if let file = try? resultsDirectory().appendingPathComponent(id) {
        try? FileManager.default.removeItem(at: file)
      }
    }
    result(nil)
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let id = downloadTask.taskDescription else { return }
    let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200...299).contains(status) else {
      failures[downloadTask.taskIdentifier] = FlutterError(
        code: "http",
        message: "The provider result download returned HTTP \(status).",
        details: status
      )
      return
    }
    do {
      // The file must move out of its temporary location before this
      // delegate call returns; the retained copy survives until Dart
      // releases it with completeResult.
      let destination = try resultsDirectory().appendingPathComponent(id)
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.moveItem(at: location, to: destination)
      var entries = manifest
      entries[id] = [
        "file": id,
        "contentType": downloadTask.response?.mimeType ?? "",
      ]
      manifest = entries
    } catch {
      failures[downloadTask.taskIdentifier] = FlutterError(
        code: "io",
        message: error.localizedDescription,
        details: nil
      )
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let id = task.taskDescription else { return }
    let failure = failures.removeValue(forKey: task.taskIdentifier)
    if let active = activeTasks[id], active != task.taskIdentifier {
      // A superseded transfer finished; its outcome belongs to nobody. Any
      // file it retained is already in the manifest for the current
      // transfer's completion (or the recovery pass) to pick up.
      return
    }
    activeTasks.removeValue(forKey: id)
    let pending = waiters.removeValue(forKey: id) ?? []
    // Bytes retained under this id satisfy the request no matter how this
    // particular transfer ended.
    if let payload = retainedPayload(for: id) {
      pending.forEach { $0(payload) }
      return
    }
    if let failure {
      pending.forEach { $0(failure) }
      return
    }
    if let error {
      let code = (error as NSError).code == NSURLErrorTimedOut
        ? "timeout" : "network"
      let flutterError = FlutterError(
        code: code,
        message: error.localizedDescription,
        details: nil
      )
      pending.forEach { $0(flutterError) }
      return
    }
    pending.forEach { $0(nil) }
  }

  func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
    // Invalidation would otherwise strand every waiter forever and leave a
    // dead session cached; report a retryable failure and start over.
    let stranded = waiters
    waiters = [:]
    activeTasks = [:]
    failures = [:]
    self.session = nil
    let failure = FlutterError(
      code: "network",
      message: error?.localizedDescription
        ?? "The background transfer session became invalid.",
      details: nil
    )
    stranded.values.forEach { callbacks in callbacks.forEach { $0(failure) } }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    let handlers = backgroundCompletionHandlers
    backgroundCompletionHandlers = []
    handlers.forEach { $0() }
  }

  // MARK: - Retained results

  private var manifest: [String: [String: String]] {
    get {
      UserDefaults.standard.dictionary(forKey: Self.manifestKey)
        as? [String: [String: String]] ?? [:]
    }
    set { UserDefaults.standard.set(newValue, forKey: Self.manifestKey) }
  }

  private func retainedPayload(for id: String) -> [String: String]? {
    guard let entry = manifest[id] else { return nil }
    guard let file = try? resultsDirectory().appendingPathComponent(id),
      FileManager.default.fileExists(atPath: file.path)
    else {
      var entries = manifest
      entries.removeValue(forKey: id)
      manifest = entries
      return nil
    }
    return ["path": file.path, "contentType": entry["contentType"] ?? ""]
  }

  private func resultsDirectory() throws -> URL {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    var directory = base.appendingPathComponent(
      "clawnsole_pending_results",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? directory.setResourceValues(values)
    return directory
  }

  private func sanitizedId(_ value: Any?) -> String? {
    guard let raw = (value as? String)?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ) else { return nil }
    let safeCharacters = CharacterSet.alphanumerics.union(
      CharacterSet(charactersIn: "-_")
    )
    guard !raw.isEmpty, raw.rangeOfCharacter(from: safeCharacters.inverted) == nil
    else { return nil }
    return raw
  }
}
