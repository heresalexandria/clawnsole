import 'dart:io';

/// A human name for this device, shown beside its drafts on other devices:
/// the host name with its domain suffix and dashes tidied
/// ("Alexandrias-MacBook-Pro.local" → "Alexandrias MacBook Pro"), or the
/// platform when the sandbox hides it.
String composerDeviceName() {
  var host = '';
  try {
    host = Platform.localHostname.trim();
  } on Object {
    // Some sandboxes refuse the lookup; the platform label below still names
    // the device well enough to tell it apart.
  }
  for (final suffix in const ['.local', '.lan', '.home', '.localdomain']) {
    if (host.toLowerCase().endsWith(suffix)) {
      host = host.substring(0, host.length - suffix.length);
    }
  }
  if (host.isEmpty || host.toLowerCase() == 'localhost') {
    return _platformLabel();
  }
  return host.replaceAll(RegExp(r'[-_]+'), ' ').trim();
}

/// The platform tag stored with this device's published drafts.
String composerDevicePlatform() => Platform.operatingSystem;

String _platformLabel() => switch (Platform.operatingSystem) {
  'macos' => 'Mac',
  'ios' => 'iPhone or iPad',
  'windows' => 'Windows PC',
  'linux' => 'Linux PC',
  'android' => 'Android device',
  _ => 'Device',
};
