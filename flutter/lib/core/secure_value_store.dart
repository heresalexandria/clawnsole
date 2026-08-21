abstract interface class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemorySecureValueStore implements SecureValueStore {
  MemorySecureValueStore([Map<String, String>? initial])
    : values = Map<String, String>.from(initial ?? const <String, String>{});

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class UnavailableSecureValueStore implements SecureValueStore {
  const UnavailableSecureValueStore();

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) =>
      throw StateError('Secure device storage is unavailable.');

  @override
  Future<void> delete(String key) async {}
}
