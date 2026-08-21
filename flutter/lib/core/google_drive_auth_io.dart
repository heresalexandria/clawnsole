import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'google_drive.dart';
import 'google_drive_auth_base.dart';

const _desktopClientId = String.fromEnvironment(
  'CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID',
);
const _desktopClientSecret = String.fromEnvironment(
  'CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_SECRET',
);
const _iosClientId = String.fromEnvironment('CLAWNSOLE_GOOGLE_IOS_CLIENT_ID');
const _androidServerClientId = String.fromEnvironment(
  'CLAWNSOLE_GOOGLE_ANDROID_SERVER_CLIENT_ID',
);
const _refreshTokenKey = 'clawnsole.googleDrive.refreshToken.v1';

GoogleDriveAuthorizer createPlatformGoogleDriveAuthorizer() =>
    Platform.isWindows
    ? _DesktopGoogleDriveAuthorizer()
    : (Platform.isAndroid || Platform.isIOS)
    ? _MobileGoogleDriveAuthorizer()
    : const _UnavailableIoGoogleDriveAuthorizer();

class _MobileGoogleDriveAuthorizer implements GoogleDriveAuthorizer {
  final GoogleSignIn _signIn = GoogleSignIn.instance;
  Future<void>? _initialization;

  @override
  bool get isAvailable => Platform.isAndroid
      ? _androidServerClientId.isNotEmpty
      : _iosClientId.isNotEmpty;

  @override
  String get unavailableMessage => Platform.isAndroid
      ? 'Configure CLAWNSOLE_GOOGLE_ANDROID_SERVER_CLIENT_ID and the Android OAuth package/SHA to enable Drive.'
      : 'Configure CLAWNSOLE_GOOGLE_IOS_CLIENT_ID and its reversed URL scheme to enable Drive.';

  Future<void> _initialize() => _initialization ??= _signIn.initialize(
    clientId: Platform.isIOS ? _iosClientId : null,
    serverClientId: Platform.isAndroid ? _androidServerClientId : null,
  );

  @override
  Future<String> authorize() async {
    if (!isAvailable) throw StateError(unavailableMessage);
    await _initialize();
    GoogleSignInAccount? account;
    final lightweight = _signIn.attemptLightweightAuthentication();
    if (lightweight != null) account = await lightweight;
    account ??= await _signIn.authenticate(
      scopeHint: const <String>[googleDriveFileScope],
    );
    final authorization =
        await account.authorizationClient.authorizationForScopes(const <String>[
          googleDriveFileScope,
        ]) ??
        await account.authorizationClient.authorizeScopes(const <String>[
          googleDriveFileScope,
        ]);
    return authorization.accessToken;
  }

  @override
  Future<String?> restore() async {
    if (!isAvailable) return null;
    try {
      await _initialize();
      final lightweight = _signIn.attemptLightweightAuthentication();
      if (lightweight == null) return null;
      final account = await lightweight;
      if (account == null) return null;
      final authorization = await account.authorizationClient
          .authorizationForScopes(const <String>[googleDriveFileScope]);
      final token = authorization?.accessToken.trim() ?? '';
      return token.isEmpty ? null : token;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> disconnect() async {
    if (!isAvailable) return;
    await _initialize();
    await _signIn.disconnect();
  }
}

class _DesktopGoogleDriveAuthorizer implements GoogleDriveAuthorizer {
  _DesktopGoogleDriveAuthorizer({
    FlutterSecureStorage? secureStorage,
    http.Client? client,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _client = client ?? http.Client();

  final FlutterSecureStorage _secureStorage;
  final http.Client _client;

  @override
  bool get isAvailable => _desktopClientId.isNotEmpty;

  @override
  String get unavailableMessage =>
      'Configure CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID to enable Drive on Windows.';

  @override
  Future<String> authorize() async {
    if (!isAvailable) throw StateError(unavailableMessage);
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken?.isNotEmpty == true) {
      try {
        return await _refresh(refreshToken!);
      } on Object {
        await _secureStorage.delete(key: _refreshTokenKey);
      }
    }
    return _interactiveAuthorization();
  }

  @override
  Future<String?> restore() async {
    if (!isAvailable) return null;
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken?.isNotEmpty != true) return null;
    try {
      return await _refresh(refreshToken!);
    } on Object {
      await _secureStorage.delete(key: _refreshTokenKey);
      return null;
    }
  }

  Future<String> _interactiveAuthorization() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}/oauth/google/callback';
    final state = _randomToken(32);
    final verifier = _randomToken(64);
    final challenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    final authorization =
        Uri.https('accounts.google.com', '/o/oauth2/v2/auth', <String, String>{
          'client_id': _desktopClientId,
          'redirect_uri': redirect,
          'response_type': 'code',
          'scope': googleDriveFileScope,
          'state': state,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'access_type': 'offline',
          'prompt': 'consent',
          'include_granted_scopes': 'true',
        });
    if (!await launchUrl(authorization, mode: LaunchMode.externalApplication)) {
      await server.close(force: true);
      throw StateError('Could not open Google authorization in the browser.');
    }
    try {
      final code = await _authorizationCode(
        server,
        state,
      ).timeout(const Duration(minutes: 5));
      final response = await _client.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: const <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: <String, String>{
          'client_id': _desktopClientId,
          if (_desktopClientSecret.isNotEmpty)
            'client_secret': _desktopClientSecret,
          'code': code,
          'code_verifier': verifier,
          'grant_type': 'authorization_code',
          'redirect_uri': redirect,
        },
      );
      final payload = _tokenPayload(response);
      final refresh = payload['refresh_token']?.toString();
      if (refresh?.isNotEmpty == true) {
        await _secureStorage.write(key: _refreshTokenKey, value: refresh);
      }
      return payload['access_token']?.toString() ?? '';
    } finally {
      await server.close(force: true);
    }
  }

  Future<String> _authorizationCode(HttpServer server, String state) async {
    await for (final request in server) {
      final suppliedState = request.uri.queryParameters['state'];
      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        error == null && code != null && suppliedState == state
            ? '<!doctype html><title>Clawnsole connected</title><p>Google Drive is connected. You can close this tab and return to Clawnsole.</p>'
            : '<!doctype html><title>Clawnsole connection failed</title><p>Google Drive authorization was not completed. Return to Clawnsole and try again.</p>',
      );
      await request.response.close();
      if (error != null) throw StateError('Google authorization was declined.');
      if (suppliedState != state) {
        throw StateError('Google authorization returned an invalid state.');
      }
      if (code?.isNotEmpty == true) return code!;
    }
    throw StateError('Google authorization did not return a code.');
  }

  Future<String> _refresh(String refreshToken) async {
    final response = await _client.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: const <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: <String, String>{
        'client_id': _desktopClientId,
        if (_desktopClientSecret.isNotEmpty)
          'client_secret': _desktopClientSecret,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      },
    );
    return _tokenPayload(response)['access_token']?.toString() ?? '';
  }

  Map<String, Object?> _tokenPayload(http.Response response) {
    final value = jsonDecode(response.body);
    if (value is! Map<Object?, Object?>) {
      throw StateError('Google returned an invalid token response.');
    }
    final payload = value.map((key, child) => MapEntry(key.toString(), child));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        payload['error_description']?.toString() ??
            'Google authorization failed with HTTP ${response.statusCode}.',
      );
    }
    final token = payload['access_token']?.toString() ?? '';
    if (token.isEmpty) {
      throw StateError('Google returned an empty access token.');
    }
    return payload;
  }

  @override
  Future<void> disconnect() async {
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    if (refreshToken?.isNotEmpty != true) return;
    try {
      await _client.post(
        Uri.parse('https://oauth2.googleapis.com/revoke'),
        headers: const <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: <String, String>{'token': refreshToken!},
      );
    } on Object {
      // Local disconnect succeeds even when Google is temporarily unreachable.
    }
  }

  String _randomToken(int bytes) {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(bytes, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}

class _UnavailableIoGoogleDriveAuthorizer implements GoogleDriveAuthorizer {
  const _UnavailableIoGoogleDriveAuthorizer();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableMessage =>
      'Google Drive authorization is unavailable on this native platform.';

  @override
  Future<String> authorize() => throw UnsupportedError(unavailableMessage);

  @override
  Future<String?> restore() async => null;

  @override
  Future<void> disconnect() async {}
}
