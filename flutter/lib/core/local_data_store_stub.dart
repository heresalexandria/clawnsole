import 'models.dart';

class LocalDataStore {
  Future<StoredData> read() => throw UnsupportedError(
    'Browser builds use the Clawnsole local companion service.',
  );

  Future<void> write(StoredData data) => throw UnsupportedError(
    'Browser builds use the Clawnsole local companion service.',
  );

  Future<void> delete() => throw UnsupportedError(
    'Browser builds use the Clawnsole local companion service.',
  );

  Future<StorageStats> stats(int records) => throw UnsupportedError(
    'Browser builds use the Clawnsole local companion service.',
  );
}
