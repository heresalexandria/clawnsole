import Flutter
import UIKit
import UserNotifications

/// Local "your film is ready" alerts for generations that finish while the
/// app is not in the foreground.
///
/// Dart posts through the method channel once a generation lands; the
/// background transfer session posts directly when the OS finishes a result
/// download without the app running in front. Both paths share these helpers
/// so the rules stay identical: never while the app is active (the UI already
/// shows the result), never without permission, and one alert per generation —
/// a later post for the same generation replaces the earlier alert instead of
/// stacking a duplicate.
enum CompletionNotifications {
  private static let identifierPrefix = "ai.clawnsole.generation."

  /// Reports whether alerts may be posted, prompting only while the system
  /// has no recorded answer — so the user is asked at most once.
  static func requestPermission(_ completion: @escaping (Bool) -> Void) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .notDetermined else {
        DispatchQueue.main.async { completion(allows(settings)) }
        return
      }
      center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
        DispatchQueue.main.async { completion(granted) }
      }
    }
  }

  /// Posts an alert immediately and reports whether it was posted. Runs on
  /// the main thread because it reads the application state.
  static func post(
    title: String,
    body: String,
    threadId: String?,
    completion: @escaping (Bool) -> Void
  ) {
    guard UIApplication.shared.applicationState != .active else {
      completion(false)
      return
    }
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      guard allows(settings) else {
        DispatchQueue.main.async { completion(false) }
        return
      }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      let thread = threadId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !thread.isEmpty { content.threadIdentifier = thread }
      let request = UNNotificationRequest(
        identifier: identifierPrefix + (thread.isEmpty ? UUID().uuidString : thread),
        content: content,
        trigger: nil
      )
      center.add(request) { error in
        DispatchQueue.main.async { completion(error == nil) }
      }
    }
  }

  private static func allows(_ settings: UNNotificationSettings) -> Bool {
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral: true
    default: false
    }
  }
}

final class CompletionNotificationPlugin {
  func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.clawnsole/notifications",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestPermission":
        CompletionNotifications.requestPermission { result($0) }
      case "notify":
        let arguments = call.arguments as? [String: Any]
        guard
          let title = arguments?["title"] as? String, !title.isEmpty,
          let body = arguments?["body"] as? String
        else {
          result(
            FlutterError(
              code: "invalid",
              message: "A notification needs a title and a body.",
              details: nil
            )
          )
          return
        }
        CompletionNotifications.post(
          title: title,
          body: body,
          threadId: arguments?["threadId"] as? String
        ) { result($0) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
