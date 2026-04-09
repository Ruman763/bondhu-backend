import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for secrets: encryption keys, E2E private keys, tokens.
/// - Mobile: Keychain (iOS), EncryptedSharedPreferences/Keystore (Android).
/// - Web: WebCrypto-backed storage (HTTPS or localhost). Requires init on all platforms.
/// Do not store large or high-churn data here; use [EncryptedLocalStore] for that.
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService _instance = SecureStorageService._();
  static SecureStorageService get instance => _instance;

  static const String _keyDbEncryption = 'bondhu_db_encryption_key';
  static const String _keyE2EPrivate = 'bondhu_e2e_private_key'; // Future E2E
  static const String _keyE2EPublic = 'bondhu_e2e_public_key';
  static const String _keyE2EPin = 'bondhu_e2e_pin';
  static const String _keyMessageSyncAes = 'bondhu_msg_sync_aes_key';
  static const String _keyMessageVault = 'bondhu_msg_vault_aes_key';

  late final FlutterSecureStorage _storage;
  bool _initialized = false;

  /// Call once after WidgetsBinding.ensureInitialized().
  /// On web, uses WebCrypto-backed storage (works on HTTPS or localhost).
  static Future<void> init() async {
    if (_instance._initialized) return;
    if (kIsWeb) {
      _instance._storage = const FlutterSecureStorage(
        webOptions: WebOptions(
          dbName: 'bondhu_secure',
          publicKey: 'bondhu_web_secure_v1',
        ),
      );
    } else {
      const androidOptions = AndroidOptions(
        encryptedSharedPreferences: true,
        resetOnError: true,
      );
      const iosOptions = IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      );
      _instance._storage = const FlutterSecureStorage(
        aOptions: androidOptions,
        iOptions: iosOptions,
      );
    }
    _instance._initialized = true;
  }

  /// Read a raw string (e.g. base64 key).
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      if (kDebugMode) debugPrint('[SecureStorage] read error: $e');
      return null;
    }
  }

  /// Write a string.
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      if (kDebugMode) debugPrint('[SecureStorage] write error: $e');
    }
  }

  /// Delete a key.
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }

  /// Get or create the 256-bit key used for [EncryptedLocalStore].
  /// Stored in secure storage so encrypted Hive box can be opened.
  Future<Uint8List> getOrCreateDbEncryptionKey() async {
    const keyLength = 32; // 256 bits for AES-256
    final existing = await read(_keyDbEncryption);
    if (existing != null && existing.isNotEmpty) {
      try {
        return Uint8List.fromList(base64Url.decode(existing));
      } catch (_) {}
    }
    final random = Random.secure();
    final key = Uint8List(keyLength);
    for (var i = 0; i < keyLength; i++) {
      key[i] = random.nextInt(256);
    }
    await write(_keyDbEncryption, base64Url.encode(key));
    return key;
  }

  /// Store the DB encryption key (when generated externally).
  Future<void> setDbEncryptionKey(Uint8List key) async {
    await write(_keyDbEncryption, base64Url.encode(key));
  }

  /// E2E private key (JWK string) for future end-to-end encryption.
  Future<String?> getE2EPrivateKey() => read(_keyE2EPrivate);
  Future<void> setE2EPrivateKey(String? value) async {
    if (value == null) {
      await delete(_keyE2EPrivate);
    } else {
      await write(_keyE2EPrivate, value);
    }
  }

  /// E2E public key (JWK string).
  Future<String?> getE2EPublicKey() => read(_keyE2EPublic);
  Future<void> setE2EPublicKey(String? value) async {
    if (value == null) {
      await delete(_keyE2EPublic);
    } else {
      await write(_keyE2EPublic, value);
    }
  }

  /// Local PIN/passphrase used to protect or restore E2E backups (for Google/OAuth accounts).
  Future<String?> getE2EPin() => read(_keyE2EPin);
  Future<void> setE2EPin(String? value) async {
    if (value == null || value.isEmpty) {
      await delete(_keyE2EPin);
    } else {
      await write(_keyE2EPin, value);
    }
  }

  /// AES-256 key (base64) for legacy bms2 rows (PBKDF2 from login password + profile salt).
  Future<String?> getMessageSyncAesKeyBase64() => read(_keyMessageSyncAes);
  Future<void> setMessageSyncAesKeyBase64(String? value) async {
    if (value == null || value.isEmpty) {
      await delete(_keyMessageSyncAes);
    } else {
      await write(_keyMessageSyncAes, value);
    }
  }

  /// Random AES-256 key (base64) for bms3 cloud message rows — not stored on server.
  Future<String?> getMessageVaultKeyBase64() => read(_keyMessageVault);
  Future<void> setMessageVaultKeyBase64(String? value) async {
    if (value == null || value.isEmpty) {
      await delete(_keyMessageVault);
    } else {
      await write(_keyMessageVault, value);
    }
  }

  /// Clears E2E keys, message sync keys, vault key, and backup PIN so another account cannot reuse them after logout.
  Future<void> clearE2ESessionSecrets() async {
    await delete(_keyE2EPrivate);
    await delete(_keyE2EPublic);
    await delete(_keyE2EPin);
    await delete(_keyMessageSyncAes);
    await delete(_keyMessageVault);
  }
}
