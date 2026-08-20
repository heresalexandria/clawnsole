import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS Google Sign-In initializes App Check on physical devices', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final debugConfig = File('ios/Flutter/Debug.xcconfig').readAsStringSync();
    final releaseConfig = File(
      'ios/Flutter/Release.xcconfig',
    ).readAsStringSync();
    final buildHelpers = File('scripts/_common.sh').readAsStringSync();

    expect(appDelegate, contains('import GoogleSignIn'));
    expect(appDelegate, contains('#if !targetEnvironment(simulator)'));
    expect(
      appDelegate,
      contains('object(forInfoDictionaryKey: "GIDClientID")'),
    );
    expect(
      appDelegate,
      contains('GIDSignIn.sharedInstance.configure { error in'),
    );
    expect(
      infoPlist,
      contains(
        '<key>GIDClientID</key>\n\t<string>\$(GOOGLE_IOS_CLIENT_ID)</string>',
      ),
    );
    expect(debugConfig, contains('GOOGLE_IOS_CLIENT_ID ='));
    expect(releaseConfig, contains('GOOGLE_IOS_CLIENT_ID ='));
    expect(buildHelpers, contains('GOOGLE_IOS_CLIENT_ID = %s'));
  });

  test('every iOS app configuration signs with production App Attest', () {
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(
      entitlements,
      contains('com.apple.developer.devicecheck.appattest-environment'),
    );
    expect(entitlements, contains('<string>production</string>'));
    expect(project, contains('com.apple.AppAttest'));
    expect(
      RegExp(
        r'CODE_SIGN_ENTITLEMENTS = Runner/Runner\.entitlements;',
      ).allMatches(project),
      hasLength(3),
    );
  });
}
