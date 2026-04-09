import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'secure_storage_service.dart';

/// Encrypted local storage for sensitive app data (chat history, local user cache).
/// Data is encrypted at rest using AES-256; the key is stored in [SecureStorageService].
/// Comparable to web's IndexedDB + E2E: data stays on device and is encrypted.
class EncryptedLocalStore {
  EncryptedLocalStore._();
  static final EncryptedLocalStore _instance = EncryptedLocalStore._();
  static EncryptedLocalStore get instance => _instance;

  static const String _boxName = 'bondhu_encrypted';
  Box<dynamic>? _box;
  bool _initialized = false;

  /// Call once after [SecureStorageService.init] and Hive.init (from init() below).
  static Future<void> init() async {
    if (_instance._initialized) return;
    try {
      final key = await SecureStorageService.instance.getOrCreateDbEncryptionKey();
      if (key.length != 32) {
        if (kDebugMode) debugPrint('[EncryptedLocalStore] Invalid key length');
        return;
      }
      _instance._box = await Hive.openBox(
        _boxName,
        encryptionCipher: HiveAesCipher(key),
      );
      _instance._initialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[EncryptedLocalStore] init error: $e');
    }
  }

  Box<dynamic>? get _b => _box;

  Future<String?> getString(String key) async {
    try {
      final v = _b?.get(key);
      if (v == null) return null;
      return v is String ? v : v.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> setString(String key, String value) async {
    try {
      await _b?.put(key, value);
    } catch (e) {
      if (kDebugMode) debugPrint('[EncryptedLocalStore] setString error: $e');
    }
  }

  Future<void> remove(String key) async {
    try {
      await _b?.delete(key);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await _b?.clear();
    } catch (_) {}
  }

  /// Whether the store is ready (encrypted box opened).
  bool get isReady => _initialized && _box != null;
}
