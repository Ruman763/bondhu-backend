import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'secure_storage_service.dart';

/// Cloud-synced message rows use AES-GCM.
/// - **bms3:** random 256-bit vault key (device-only). DB leak does not reveal the key.
/// - **bms2:** legacy PBKDF2(email+password, profile salt) — still decrypted if legacy key exists after login.
class MessageSyncCryptoService {
  MessageSyncCryptoService._();
  static final MessageSyncCryptoService instance = MessageSyncCryptoService._();

  static const String payloadPrefixV2 = 'bms2:';
  static const String payloadPrefixV3 = 'bms3:';
  static const int _kdfIterations = 200000;
  static const int _aesKeyLength = 32;
  static const int _gcmIvLength = 12;
  static const int _gcmTagLength = 128;
  // Web resilience fallback: keeps keys available in current app session
  // if secure storage is unavailable (private mode / browser policy).
  String? _sessionVaultKeyB64;
  String? _sessionLegacyKeyB64;

  static Uint8List sha256Bytes(Uint8List data) {
    return SHA256Digest().process(data);
  }

  Uint8List _deriveLegacyKeyBytes(String email, String password, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _kdfIterations, _aesKeyLength));
    final input = Uint8List.fromList(utf8.encode('${email.trim().toLowerCase()}\x00$password'));
    return derivator.process(input);
  }

  /// Legacy: login password + profile salt (for reading old bms2 rows only).
  Future<void> cacheKeyFromPassword({
    required String email,
    required String password,
    required String? messageCryptoSaltB64,
  }) async {
    final saltB64 = messageCryptoSaltB64?.trim();
    if (saltB64 == null || saltB64.isEmpty) return;
    Uint8List salt;
    try {
      salt = Uint8List.fromList(base64.decode(saltB64));
    } catch (_) {
      return;
    }
    final key = _deriveLegacyKeyBytes(email, password, salt);
    final b64 = base64Encode(key);
    await SecureStorageService.instance.setMessageSyncAesKeyBase64(b64);
    _sessionLegacyKeyB64 = b64;
  }

  /// Creates a random vault key on this device if missing (not derived from password; not on server).
  Future<void> ensureMessageVaultKey() async {
    final existing = await SecureStorageService.instance.getMessageVaultKeyBase64();
    if (existing != null && existing.isNotEmpty) {
      _sessionVaultKeyB64 = existing;
      return;
    }
    if (_sessionVaultKeyB64 != null && _sessionVaultKeyB64!.isNotEmpty) return;
    final k = Uint8List(_aesKeyLength);
    final r = Random.secure();
    for (var i = 0; i < _aesKeyLength; i++) {
      k[i] = r.nextInt(256);
    }
    final b64 = base64Encode(k);
    await SecureStorageService.instance.setMessageVaultKeyBase64(b64);
    // Always keep in-memory copy so this session can still migrate
    // even when secure storage write is blocked by browser policy.
    _sessionVaultKeyB64 = b64;
  }

  String _sealUtf8(Uint8List aesKey32, String plain) {
    final iv = Uint8List(_gcmIvLength);
    for (var i = 0; i < _gcmIvLength; i++) {
      iv[i] = Random.secure().nextInt(256);
    }
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(aesKey32), _gcmTagLength, iv, Uint8List(0)),
      );
    final plainBytes = utf8.encode(plain);
    final cipherWithTag = cipher.process(Uint8List.fromList(plainBytes));
    final payload = {
      'v': 1,
      'iv': base64.encode(iv),
      'c': base64.encode(cipherWithTag),
    };
    return base64.encode(utf8.encode(jsonEncode(payload)));
  }

  String? _openUtf8(Uint8List aesKey32, String outerB64) {
    Map<String, dynamic> payload;
    try {
      final jsonStr = utf8.decode(base64.decode(outerB64.trim()));
      payload = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final iv = Uint8List.fromList(base64.decode(payload['iv'] as String? ?? ''));
    final c = Uint8List.fromList(base64.decode(payload['c'] as String? ?? ''));
    if (iv.length != _gcmIvLength || c.isEmpty) return null;
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(aesKey32), _gcmTagLength, iv, Uint8List(0)),
        );
      final plain = cipher.process(c);
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  /// Seal JSON for chat migration (AES-256-GCM with key = SHA256(tokenBytes)).
  String sealMigrationInner(Uint8List tokenBytes, String innerJsonUtf8) {
    final key = sha256Bytes(tokenBytes);
    return _sealUtf8(key, innerJsonUtf8);
  }

  String? unsealMigrationInner(Uint8List tokenBytes, String sealedOuterB64) {
    final key = sha256Bytes(tokenBytes);
    return _openUtf8(key, sealedOuterB64);
  }

  Future<String?> encryptPlaintext(String plain) async {
    await ensureMessageVaultKey();
    final keyB64 = (await SecureStorageService.instance.getMessageVaultKeyBase64()) ?? _sessionVaultKeyB64;
    if (keyB64 == null || keyB64.isEmpty) return null;
    Uint8List key;
    try {
      key = Uint8List.fromList(base64.decode(keyB64));
    } catch (_) {
      return null;
    }
    if (key.length != _aesKeyLength) return null;
    final inner = _sealUtf8(key, plain);
    return '$payloadPrefixV3$inner';
  }

  Future<String?> decryptStoredPayload(String stored) async {
    if (stored.startsWith(payloadPrefixV3)) {
      final inner = stored.substring(payloadPrefixV3.length).trim();
      if (inner.isEmpty) return null;
      final keyB64 = await SecureStorageService.instance.getMessageVaultKeyBase64();
      final effectiveKeyB64 = (keyB64 != null && keyB64.isNotEmpty) ? keyB64 : _sessionVaultKeyB64;
      if (effectiveKeyB64 == null || effectiveKeyB64.isEmpty) return null;
      Uint8List key;
      try {
        key = Uint8List.fromList(base64.decode(effectiveKeyB64));
      } catch (_) {
        return null;
      }
      return _openUtf8(key, inner);
    }
    if (stored.startsWith(payloadPrefixV2)) {
      final inner = stored.substring(payloadPrefixV2.length).trim();
      if (inner.isEmpty) return null;
      final keyB64 = await SecureStorageService.instance.getMessageSyncAesKeyBase64();
      final effectiveKeyB64 = (keyB64 != null && keyB64.isNotEmpty) ? keyB64 : _sessionLegacyKeyB64;
      if (effectiveKeyB64 == null || effectiveKeyB64.isEmpty) return null;
      Uint8List key;
      try {
        key = Uint8List.fromList(base64.decode(effectiveKeyB64));
      } catch (_) {
        return null;
      }
      return _openUtf8(key, inner);
    }
    return null;
  }

  static bool isDbSyncPayload(String s) => s.startsWith(payloadPrefixV2) || s.startsWith(payloadPrefixV3);

  /// Keys to pack for WeChat-style migration (new phone gets these via QR + one-time server blob).
  Future<Map<String, String>> exportKeyMaterialForMigration() async {
    final out = <String, String>{};
    final vk = (await SecureStorageService.instance.getMessageVaultKeyBase64()) ?? _sessionVaultKeyB64;
    if (vk != null && vk.isNotEmpty) out['vk'] = vk;
    final lk = (await SecureStorageService.instance.getMessageSyncAesKeyBase64()) ?? _sessionLegacyKeyB64;
    if (lk != null && lk.isNotEmpty) out['lk'] = lk;
    return out;
  }

  Future<void> applyImportedKeyMaterial(Map<String, dynamic> map) async {
    final vk = map['vk'] as String?;
    if (vk != null && vk.isNotEmpty) {
      await SecureStorageService.instance.setMessageVaultKeyBase64(vk);
      _sessionVaultKeyB64 = vk;
    }
    final lk = map['lk'] as String?;
    if (lk != null && lk.isNotEmpty) {
      await SecureStorageService.instance.setMessageSyncAesKeyBase64(lk);
      _sessionLegacyKeyB64 = lk;
    }
  }
}
