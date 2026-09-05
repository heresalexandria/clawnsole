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
    ? DesktopGoogleDriveAuthorizer()
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
  Future<String?> authorizeSilently() async {
    if (!isAvailable) return null;
    try {
      await _initialize();
      final lightweight = _signIn.attemptLightweightAuthentication();
      if (lightweight == null) return null;
      final account = await lightweight;
      if (account == null) return null;
      // authorizationForScopes never prompts; a session without the Drive
      // grant simply stays disconnected until the user reconnects.
      final authorization = await account.authorizationClient
          .authorizationForScopes(const <String>[googleDriveFileScope]);
      return authorization?.accessToken;
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

class DesktopGoogleDriveAuthorizer implements GoogleDriveAuthorizer {
  DesktopGoogleDriveAuthorizer({
    FlutterSecureStorage? secureStorage,
    http.Client? client,
    String clientId = _desktopClientId,
    String clientSecret = _desktopClientSecret,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _client = client ?? http.Client(),
       _clientId = clientId,
       _clientSecret = clientSecret;

  final FlutterSecureStorage _secureStorage;
  final http.Client _client;
  final String _clientId;
  final String _clientSecret;

  @override
  bool get isAvailable => _clientId.isNotEmpty;

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
      } on _GoogleTokenException catch (error) {
        if (!error.refreshTokenRejected) rethrow;
        await _secureStorage.delete(key: _refreshTokenKey);
      }
    }
    return _interactiveAuthorization();
  }

  @override
  Future<String?> authorizeSilently() async {
    if (!isAvailable) return null;
    try {
      final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
      if (refreshToken?.isNotEmpty != true) return null;
      try {
        return await _refresh(refreshToken!);
      } on _GoogleTokenException catch (error) {
        if (error.refreshTokenRejected) {
          await _secureStorage.delete(key: _refreshTokenKey);
        }
        return null;
      }
    } on Object {
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
          'client_id': _clientId,
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
          'client_id': _clientId,
          if (_clientSecret.isNotEmpty) 'client_secret': _clientSecret,
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
    final response = await _client
        .post(
          Uri.parse('https://oauth2.googleapis.com/token'),
          headers: const <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: <String, String>{
            'client_id': _clientId,
            if (_clientSecret.isNotEmpty) 'client_secret': _clientSecret,
            'refresh_token': refreshToken,
            'grant_type': 'refresh_token',
          },
        )
        .timeout(const Duration(seconds: 30));
    return _tokenPayload(response)['access_token']?.toString() ?? '';
  }

  Map<String, Object?> _tokenPayload(http.Response response) {
    final value = jsonDecode(response.body);
    if (value is! Map<Object?, Object?>) {
      throw StateError('Google returned an invalid token response.');
    }
    final payload = value.map((key, child) => MapEntry(key.toString(), child));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _GoogleTokenException(
        response.statusCode,
        payload['error']?.toString(),
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

class _GoogleTokenException implements Exception {
  const _GoogleTokenException(this.status, this.oauthError);

  final int status;
  final String? oauthError;

  bool get refreshTokenRejected =>
      status == 400 && oauthError == 'invalid_grant';

  @override
  String toString() => 'Google authorization failed with HTTP $status.';
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
  Future<String?> authorizeSilently() async => null;

  @override
  Future<void> disconnect() async {}
}
