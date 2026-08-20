import Flutter
import GoogleSignIn
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureGoogleSignInAppCheck()
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
