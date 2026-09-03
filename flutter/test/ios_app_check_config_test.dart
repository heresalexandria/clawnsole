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
    expect(releaseConfig, contains('#include? "CISigning.xcconfig"'));
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

  test('iOS media picker declares its transitive location purpose', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(
      infoPlist,
      contains('<key>NSLocationWhenInUseUsageDescription</key>'),
    );
    expect(
      infoPlist,
      contains('Clawnsole does not request your current location.'),
    );
  });

  test('Apple image sequences preserve their prompt and frame progress', () {
    final plugin = File(
      'ios/Runner/AppleLocalGenerationPlugin.swift',
    ).readAsStringSync();

    expect(plugin, contains('.text(request.prompt)'));
    expect(plugin, contains(r'\(index + 1) of \(frameCount)'));
    expect(
      plugin,
      contains(r'Generating image \(index + 1) of \(request.frameCount)'),
    );
    expect(plugin, isNot(contains('request.promptForFrame')));
  });

  test(
    'iOS keeps a purpose string for every protected API the binary links',
    () {
      final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
      // App Store Connect rejects an upload (ITMS-90683) when the binary links
      // an API guarded by a purpose string that Info.plist does not carry, even
      // if the app never calls it. The media-picker plugins link the camera and
      // photo APIs, so these keys must stay even when the app itself does not
      // use them. Builds 118 and 119 were refused for the missing camera key.
      for (final key in <String>[
        'NSCameraUsageDescription',
        'NSPhotoLibraryUsageDescription',
        'NSPhotoLibraryAddUsageDescription',
        'NSAppleMusicUsageDescription',
        'NSLocationWhenInUseUsageDescription',
      ]) {
        final match = RegExp(
          '<key>$key</key>\\s*<string>([^<]*)</string>',
        ).firstMatch(infoPlist);
        expect(match, isNotNull, reason: '$key is missing from Info.plist');
        expect(
          match!.group(1)!.trim(),
          isNotEmpty,
          reason: '$key needs a user-facing purpose string',
        );
      }
    },
  );
}
