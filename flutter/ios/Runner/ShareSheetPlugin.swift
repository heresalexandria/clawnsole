import Flutter
import UIKit

/// Presents the system share sheet for a media file Dart staged in the
/// temporary directory under its user-facing file name.
final class ShareSheetPlugin {
  func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "ai.clawnsole/share",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak controller] call, result in
      guard call.method == "share" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let controller else {
        result(
          FlutterError(
            code: "unavailable",
            message: "The share sheet has no window to open from.",
            details: nil
          )
        )
        return
      }
      Self.share(call, from: controller, result)
    }
  }

  private static func share(
    _ call: FlutterMethodCall,
    from controller: UIViewController,
    _ result: @escaping FlutterResult
  ) {
    let arguments = call.arguments as? [String: Any]
    guard
      let path = arguments?["path"] as? String,
      FileManager.default.fileExists(atPath: path)
    else {
      result(
        FlutterError(
          code: "invalid",
          message: "The media file to share is missing.",
          details: nil
        )
      )
      return
    }
    let activity = UIActivityViewController(
      activityItems: [URL(fileURLWithPath: path)],
      applicationActivities: nil
    )
    // Mail reads its subject line through this long-standing private key;
    // the responds check keeps a runtime without it from raising an
    // unknown-key exception instead of quietly dropping the subject.
    if let subject = arguments?["subject"] as? String, !subject.isEmpty,
      activity.responds(to: NSSelectorFromString("setSubject:"))
    {
      activity.setValue(subject, forKey: "subject")
    }
    // Whatever is already presented over the Flutter view must host the
    // sheet, or UIKit drops the presentation with only a console warning.
    var host = controller
    while let presented = host.presentedViewController, !presented.isBeingDismissed {
      host = presented
    }
    if let popover = activity.popoverPresentationController {
      // iPad needs an anchor; an arrowless popover centred on the window
      // reads as a plain sheet.
      let anchor: UIView = host.view
      popover.sourceView = anchor
      popover.sourceRect = CGRect(
        x: anchor.bounds.midX,
        y: anchor.bounds.midY,
        width: 0,
        height: 0
      )
      popover.permittedArrowDirections = []
    }
    var reported = false
    activity.completionWithItemsHandler = { _, completed, _, _ in
      guard !reported else { return }
      reported = true
      result(completed)
    }
    host.present(activity, animated: true)
  }
}
