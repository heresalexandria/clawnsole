import Flutter
import GoogleSignIn
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let appleLocalPlugin = AppleLocalGenerationPlugin()
  private let backgroundActivityPlugin = BackgroundActivityPlugin()
  private let backgroundDeliveryPlugin = BackgroundDeliveryPlugin()
  private let completionNotificationPlugin = CompletionNotificationPlugin()
  private let shareSheetPlugin = ShareSheetPlugin()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureGoogleSignInAppCheck()
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      appleLocalPlugin.register(with: controller)
      backgroundActivityPlugin.register(with: controller)
      backgroundDeliveryPlugin.register(with: controller)
      completionNotificationPlugin.register(with: controller)
      shareSheetPlugin.register(with: controller)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    if identifier == BackgroundDeliveryPlugin.sessionIdentifier {
      backgroundDeliveryPlugin.handleSessionEvents(completionHandler: completionHandler)
      return
    }
    super.application(
      application,
      handleEventsForBackgroundURLSession: identifier,
      completionHandler: completionHandler
    )
  }

  private func configureGoogleSignInAppCheck() {
    #if !targetEnvironment(simulator)
    guard
      let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
      clientID.hasSuffix(".apps.googleusercontent.com")
    else {
      return
    }
    GIDSignIn.sharedInstance.configure { error in
      if let error = error {
        NSLog(
          "Clawnsole could not configure Google Sign-In App Check: %@",
          error.localizedDescription
        )
      }
    }
    #endif
  }
}
