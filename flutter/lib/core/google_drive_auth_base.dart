abstract interface class GoogleDriveAuthorizer {
  bool get isAvailable;
  String get unavailableMessage;

  Future<String> authorize();

  /// Returns an access token without any user interaction — from a stored
  /// refresh token or an existing session — or null when no silent grant is
  /// possible. Never opens a browser window or sign-in sheet, and never
  /// throws; startup resume depends on both guarantees.
  Future<String?> authorizeSilently();

  Future<void> disconnect();
}
