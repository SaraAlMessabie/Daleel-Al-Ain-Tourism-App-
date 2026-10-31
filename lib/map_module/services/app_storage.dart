import 'dart:convert';

import 'app_storage_backend.dart';

class AppStorage {
  AppStorage({StorageBackend? backend})
    : _backend = backend ?? createStorageBackend();

  static const String _stateKey = 'al_ain_user_state_v1';

  final StorageBackend _backend;

  Future<Map<String, Object?>> readState() async {
    try {
      final value = await _backend.read(_stateKey);
      if (value == null || value.isEmpty) {
        return <String, Object?>{};
      }
      return Map<String, Object?>.from(jsonDecode(value) as Map);
    } catch (_) {
      return <String, Object?>{};
    }
  }

  Future<void> writeState(Map<String, Object?> state) async {
    try {
      await _backend.write(_stateKey, jsonEncode(state));
    } catch (_) {
      // Persistence is optional; the rest of the map remains usable.
    }
  }
}
