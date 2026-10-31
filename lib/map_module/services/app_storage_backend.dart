export 'app_storage_backend_native.dart';

abstract class StorageBackend {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}
