import 'package:shared_preferences/shared_preferences.dart';

import 'app_storage_backend.dart';

/// DALEEL: stores the map's favourites / trips with shared_preferences
/// (works on Android and iOS without any native code).
StorageBackend createStorageBackend() => _PrefsStorageBackend();

class _PrefsStorageBackend implements StorageBackend {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }
}
