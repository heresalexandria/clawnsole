import Flutter
import Foundation

/// Keeps native iCloud Drive operations and publication URLs behind the app's
/// platform boundary. The shared service owns the durable recovery journal.
final class ICloudReferenceHostingPlugin {
  private var service: ICloudReferenceHosting?

  func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.clawnsole/icloud_reference_host",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      guard ["status", "prepare", "lease", "leases", "cleanup", "cancel"].contains(call.method) else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard call.arguments == nil || call.arguments is [String: Any] else {
        result(FlutterError(code: "invalid", message: "Invalid iCloud hosting request.", details: nil))
        return
      }
      guard let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first else {
        result(FlutterError(code: "unavailable", message: "Local iCloud recovery storage is unavailable.", details: nil))
        return
      }
      if self.service == nil {
        self.service = ICloudReferenceHosting(
          configuration: .appContainer("iCloud.app.clawnsole.clawnsole"),
          journalDirectory: applicationSupport.appendingPathComponent(
            "Clawnsole/iCloudReferenceHosting", isDirectory: true
          )
        )
      }
      guard let service = self.service else { return }
      let method = call.method
      let arguments = call.arguments as? [String: Any] ?? [:]
      // Concurrent requests let cancel reach the actor while prepare is waiting
      // for an upload. Neither container discovery nor publication blocks UI.
      Task.detached {
        let response = await service.handle(method: method, arguments: arguments)
        await MainActor.run { result(response) }
      }
    }
  }
}
