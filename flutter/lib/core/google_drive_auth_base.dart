abstract interface class GoogleDriveAuthorizer {
  bool get isAvailable;
  String get unavailableMessage;

  Future<String> authorize();
  Future<void> disconnect();
}
