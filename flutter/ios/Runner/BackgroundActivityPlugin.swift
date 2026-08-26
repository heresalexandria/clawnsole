import Flutter
import UIKit

/// Keeps the process executing briefly after the app is backgrounded while
/// provider work (a submission, status poll, or result download) is pending.
///
/// Without this, iOS suspends the app almost immediately after a switch to
/// another app, freezing the Dart poll timer and killing in-flight provider
/// requests, so short generations and near-complete downloads are lost until
/// the user returns — sometimes after the provider's retention window has
/// already expired. A finite `beginBackgroundTask` window lets that work land.
final class BackgroundActivityPlugin: NSObject {
  private var pendingWork = false
  private var taskId: UIBackgroundTaskIdentifier = .invalid

  func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.clawnsole/background_activity",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "setPendingWork":
        let arguments = call.arguments as? [String: Any]
        self.setPendingWork(arguments?["pending"] as? Bool ?? false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(appDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(appDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  private func setPendingWork(_ pending: Bool) {
    pendingWork = pending
    if !pending {
      // All provider work has landed; hand the remaining time back so the
      // system does not count an idle window against the app.
      endTask()
    } else if UIApplication.shared.applicationState == .background {
      beginTaskIfNeeded()
    }
  }

  @objc private func appDidEnterBackground() {
    if pendingWork { beginTaskIfNeeded() }
  }

  @objc private func appDidBecomeActive() {
    endTask()
  }

  private func beginTaskIfNeeded() {
    guard taskId == .invalid else { return }
    // The expiration handler ends the identifier it was created with, not
    // whatever taskId holds by then: when remaining background time is near
    // zero the system can run the handler before the assignment below is
    // observed, and ending the captured identifier can never leak the task.
    var identifier = UIBackgroundTaskIdentifier.invalid
    identifier = UIApplication.shared.beginBackgroundTask(
      withName: "ClawnsoleGenerationWork"
    ) { [weak self] in
      if let self, self.taskId == identifier {
        self.endTask()
      } else if identifier != .invalid {
        UIApplication.shared.endBackgroundTask(identifier)
      }
    }
    taskId = identifier
  }

  private func endTask() {
    guard taskId != .invalid else { return }
    UIApplication.shared.endBackgroundTask(taskId)
    taskId = .invalid
  }
}
