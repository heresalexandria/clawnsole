import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

const clawnsoleIosAppStoreId = '6801916362';
const clawnsoleAndroidPackageId = 'app.clawnsole.clawnsole';

/// The store destination for a supported mobile platform.
class StoreUpdateDestination {
  const StoreUpdateDestination({
    required this.name,
    required this.appUri,
    required this.webUri,
  });

  final String name;
  final Uri appUri;
  final Uri webUri;
}

StoreUpdateDestination? clawnsoleStoreDestination(TargetPlatform platform) =>
    switch (platform) {
      TargetPlatform.iOS => StoreUpdateDestination(
        name: 'App Store',
        appUri: Uri.parse(
          'itms-apps://apps.apple.com/app/id$clawnsoleIosAppStoreId',
        ),
        webUri: Uri.parse(
          'https://apps.apple.com/app/id$clawnsoleIosAppStoreId',
        ),
      ),
      TargetPlatform.android => StoreUpdateDestination(
        name: 'Google Play',
        appUri: Uri.parse('market://details?id=$clawnsoleAndroidPackageId'),
        webUri: Uri.parse(
          'https://play.google.com/store/apps/details?id='
          '$clawnsoleAndroidPackageId',
        ),
      ),
      _ => null,
    };

typedef StoreUriLauncher = Future<bool> Function(Uri uri);
typedef StoreUpdateOpener = Future<bool> Function(TargetPlatform platform);

/// Opens the native store app and falls back to its HTTPS product page.
Future<bool> openClawnsoleStore(
  TargetPlatform platform, {
  StoreUriLauncher? launch,
}) async {
  final destination = clawnsoleStoreDestination(platform);
  if (destination == null) return false;
  final launcher = launch ?? _launchExternally;
  try {
    if (await launcher(destination.appUri)) return true;
  } on Object {
    // Fall through to the public product page.
  }
  try {
    return await launcher(destination.webUri);
  } on Object {
    return false;
  }
}

Future<bool> _launchExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
