import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:pointycastle/export.dart';

import 'secure_storage_service.dart';

/// Military-grade E2E encryption: RSA-OAEP (2048, SHA-256) + AES-256-GCM.
/// Payload format matches web (bondhu-v2 encryption.js) for cross-platform compatibility.
class E2EEncryptionService {
  E2EEncryptionService._();
  static final E2EEncryptionService _instance = E2EEncryptionService._();
  static E2EEncryptionService get instance => _instance;

  static const int _payloadVersion = 2;
  static const int _rsaBitLength = 2048;
  static const int _aesKeyLength = 32;
  static const int _gcmIvLength = 12;
  static const int _gcmTagLength = 128;
  static const int _backupKdfKeyLength = 32;

  final _random = FortunaRandom();
  bool _randomSeeded = false;

  void _seedRandom() {
    if (_randomSeeded) return;
    _random.seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => Random.secure().nextInt(256)))));
    _randomSeeded = true;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt r = BigInt.zero;
    for (var i = 0; i < bytes.length; i++) {
      r = (r << 8) | BigInt.from(bytes[i] & 0xff);
    }
    return r;
  }

  static Uint8List _bigIntToBytes(BigInt n) {
    if (n == BigInt.zero) return Uint8List.fromList([0]);
    final hex = n.toRadixString(16);
    final len = (hex.length + 1) >> 1;
    final out = Uint8List(len);
    for (var i = 0; i < hex.length; i += 2) {
      final chunk = hex.length - i >= 2 ? hex.substring(i, i + 2) : hex.substring(i);
      out[(i >> 1)] = int.parse(chunk, radix: 16);
    }
    return out;
  }

  /// Generate RSA 2048 key pair. Public as JWK string, private stored in SecureStorage.
  Future<Map<String, String>?> generateKeyPair() async {
    try {
      _seedRandom();
      final keyGen = RSAKeyGenerator()
        ..init(
          ParametersWithRandom(
            RSAKeyGeneratorParameters(BigInt.from(65537), _rsaBitLength, 64),
            _random,
          ),
        );
      final pair = keyGen.generateKeyPair();
      final pub = pair.publicKey as RSAPublicKey;
      final priv = pair.privateKey as RSAPrivateKey;
      final pubJwk = _publicKeyToJwk(pub);
      final privJwk = _privateKeyToJwk(priv);
      await SecureStorageService.instance.setE2EPrivateKey(privJwk);
      await SecureStorageService.instance.setE2EPublicKey(pubJwk);
      return {'public': pubJwk, 'private': privJwk};
    } catch (e) {
      if (kDebugMode) debugPrint('[E2E] generateKeyPair error: $e');
      return null;
    }
  }

  String _publicKeyToJwk(RSAPublicKey key) {
    final n = base64Url.encode(_bigIntToBytes(key.modulus!)).replaceAll('=', '');
    final e = base64Url.encode(_bigIntToBytes(key.exponent!)).replaceAll('=', '');
    return jsonEncode({'kty': 'RSA', 'n': n, 'e': e});
  }

  String _privateKeyToJwk(RSAPrivateKey key) {
    final n = base64Url.encode(_bigIntToBytes(key.modulus!)).replaceAll('=', '');
    final e = base64Url.encode(_bigIntToBytes(key.publicExponent!)).replaceAll('=', '');
    final d = base64Url.encode(_bigIntToBytes(key.privateExponent!)).replaceAll('=', '');
    final p = key.p != null ? base64Url.encode(_bigIntToBytes(key.p!)).replaceAll('=', '') : null;
    final q = key.q != null ? base64Url.encode(_bigIntToBytes(key.q!)).replaceAll('=', '') : null;
    return jsonEncode({
      'kty': 'RSA',
      'n': n,
      'e': e,
      'd': d,
      ...? (p != null ? {'p': p} : null),
      ...? (q != null ? {'q': q} : null),
    });
  }

  RSAPublicKey _jwkToPublicKey(String jwkStr) {
    final jwk = jsonDecode(jwkStr) as Map<String, dynamic>;
    final n = _bytesToBigInt(_decodeJwkComponent(jwk['n'] as String));
    final e = _bytesToBigInt(_decodeJwkComponent(jwk['e'] as String));
    return RSAPublicKey(n, e);
  }

  RSAPrivateKey _jwkToPrivateKey(String jwkStr) {
    final jwk = jsonDecode(jwkStr) as Map<String, dynamic>;
    final n = _bytesToBigInt(_decodeJwkComponent(jwk['n'] as String));
    final d = _bytesToBigInt(_decodeJwkComponent(jwk['d'] as String));
    final p = jwk['p'] != null ? _bytesToBigInt(_decodeJwkComponent(jwk['p'] as String)) : null;
    final q = jwk['q'] != null ? _bytesToBigInt(_decodeJwkComponent(jwk['q'] as String)) : null;
    if (p != null && q != null) return RSAPrivateKey(n, d, p, q);
    throw ArgumentError('Private JWK must include p and q (required by this client for decryption)');
  }

  String _padBase64Url(String s) {
    final remainder = s.length % 4;
    if (remainder == 0) return s;
    return s + ('=' * (4 - remainder));
  }

  /// Decode JWK component (n, e, d, p, q). Accepts base64url (Web Crypto) or standard base64 for cross-client compatibility.
  Uint8List _decodeJwkComponent(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) throw ArgumentError('Empty JWK component');
    try {
      final normalized = trimmed.replaceAll('-', '+').replaceAll('_', '/');
      final padding = (4 - normalized.length % 4) % 4;
      return Uint8List.fromList(base64.decode(normalized + ('=' * padding)));
    } catch (_) {
      try {
        return Uint8List.fromList(base64.decode(trimmed));
      } catch (_) {
        return Uint8List.fromList(base64Url.decode(_padBase64Url(trimmed)));
      }
    }
  }

  /// Encrypt plaintext for recipient (JWK string). Returns base64 payload or null.
  Future<String?> encrypt(String plainText, String recipientPublicKeyJwk) async {
    try {
      _seedRandom();
      final rsaPub = _jwkToPublicKey(recipientPublicKeyJwk);

      final aesKey = Uint8List(_aesKeyLength);
      for (var i = 0; i < _aesKeyLength; i++) {
        aesKey[i] = Random.secure().nextInt(256);
      }
      final iv = Uint8List(_gcmIvLength);
      for (var i = 0; i < _gcmIvLength; i++) {
        iv[i] = Random.secure().nextInt(256);
      }

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(KeyParameter(aesKey), _gcmTagLength, iv, Uint8List(0)),
        );
      final plainBytes = Uint8List.fromList(utf8.encode(plainText));
      final encryptedContent = cipher.process(plainBytes);
      final mac = cipher.mac;

      final cipherWithTag = Uint8List(encryptedContent.length + mac.length);
      cipherWithTag.setRange(0, encryptedContent.length, encryptedContent);
      cipherWithTag.setRange(encryptedContent.length, cipherWithTag.length, mac);

      final rsaCipher = OAEPEncoding.withSHA256(RSAEngine())
        ..init(true, ParametersWithRandom(PublicKeyParameter<RSAPublicKey>(rsaPub), _random));
      final encryptedKey = rsaCipher.process(aesKey);

      final payload = {
        'v': _payloadVersion,
        'iv': base64.encode(iv),
        'content': base64.encode(cipherWithTag),
        'key': base64.encode(encryptedKey),
      };
      return base64.encode(utf8.encode(jsonEncode(payload)));
    } catch (e) {
      if (kDebugMode) debugPrint('[E2E] encrypt error: $e');
      return null;
    }
  }

  /// Decrypt payload with our private key. Returns plaintext or fallback string.
  /// Never returns raw base64; shows a friendly message if structure is invalid or decryption fails.
  Future<String> decrypt(String packedPayloadBase64, {String? privateKeyJwk}) async {
    const fallback = '🔒 Message could not be decrypted (wrong device or key not set up)';
    try {
      String payloadJson;
      try {
        payloadJson = utf8.decode(base64.decode(packedPayloadBase64));
      } catch (_) {
        // Try base64url in case payload was encoded that way (e.g. from another client)
        try {
          final normalized = packedPayloadBase64.replaceAll('-', '+').replaceAll('_', '/');
          final padding = (4 - normalized.length % 4) % 4;
          payloadJson = utf8.decode(base64.decode(normalized + ('=' * padding)));
        } catch (_) {
          // As a final fallback, treat input as raw JSON (some clients may send the JSON payload directly)
          payloadJson = packedPayloadBase64;
        }
      }
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>?;
      if (payload == null ||
          payload['iv'] == null ||
          payload['key'] == null ||
          payload['content'] == null) {
        return fallback;
      }

      final jwk = privateKeyJwk ?? await SecureStorageService.instance.getE2EPrivateKey();
      if (jwk == null || jwk.isEmpty) return '🔒 Encrypted (set up encryption in Settings to read)';

      final rsaPriv = _jwkToPrivateKey(jwk);
      final rsaCipher = OAEPEncoding.withSHA256(RSAEngine())
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(rsaPriv));
      final encryptedKey = base64.decode(payload['key'] as String);
      final aesKey = rsaCipher.process(Uint8List.fromList(encryptedKey));

      final iv = Uint8List.fromList(base64.decode(payload['iv'] as String));
      final contentWithTag = Uint8List.fromList(base64.decode(payload['content'] as String));
      if (contentWithTag.length <= 16) return '🔒 [Encrypted Message]';

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(aesKey), _gcmTagLength, iv, Uint8List(0)),
        );
      // GCM expects ciphertext + tag; validates tag internally (may throw).
      final decrypted = cipher.process(contentWithTag);
      return utf8.decode(decrypted);
    } catch (e) {
      if (kDebugMode) debugPrint('[E2E] decrypt error: $e');
      return '🔒 Message could not be decrypted (wrong device or key not set up)';
    }
  }

  /// Key fingerprint (first 8 bytes of SHA-256 of public JWK, hex). Matches web.
  Future<String?> getKeyFingerprint(String publicKeyJwk) async {
    try {
      final jwk = jsonDecode(publicKeyJwk) as Map<String, dynamic>;
      final canonical = jsonEncode({'kty': jwk['kty'], 'n': jwk['n'], 'e': jwk['e']});
      final digest = SHA256Digest().process(Uint8List.fromList(utf8.encode(canonical)));
      final first8 = digest.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      return first8;
    } catch (_) {
      return null;
    }
  }

  /// Ensure we have a key pair; generate if missing. Returns public JWK for profile.
  Future<String?> ensureKeyPair() async {
    var pub = await SecureStorageService.instance.getE2EPublicKey();
    if (pub != null && pub.isNotEmpty) return pub;
    final pair = await generateKeyPair();
    return pair?['public'];
  }

  Future<bool> hasLocalPrivateKey() async {
    final priv = await SecureStorageService.instance.getE2EPrivateKey();
    return priv != null && priv.trim().isNotEmpty;
  }

  Future<String?> getLocalPrivateKeyJwk() async {
    final priv = await SecureStorageService.instance.getE2EPrivateKey();
    if (priv == null || priv.trim().isEmpty) return null;
    return priv.trim();
  }

  Future<String?> getLocalPublicKeyJwk() async {
    final pub = await SecureStorageService.instance.getE2EPublicKey();
    if (pub == null || pub.trim().isEmpty) return null;
    return pub.trim();
  }

  Future<void> importPrivateKeyJwk(String privateJwk) async {
    final priv = _jwkToPrivateKey(privateJwk);
    final n = base64Url.encode(_bigIntToBytes(priv.modulus!)).replaceAll('=', '');
    final e = base64Url.encode(_bigIntToBytes(priv.publicExponent!)).replaceAll('=', '');
    final pubJwk = jsonEncode({'kty': 'RSA', 'n': n, 'e': e});
    await SecureStorageService.instance.setE2EPrivateKey(privateJwk);
    await SecureStorageService.instance.setE2EPublicKey(pubJwk);
  }

  Uint8List _deriveBackupKey(String secret, Uint8List salt, int iterations) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, _backupKdfKeyLength));
    return derivator.process(Uint8List.fromList(utf8.encode(secret)));
  }

  Map<String, dynamic> _aesGcmSeal(Uint8List key, Uint8List plainBytes) {
    final iv = Uint8List(_gcmIvLength);
    for (var i = 0; i < _gcmIvLength; i++) {
      iv[i] = Random.secure().nextInt(256);
    }
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _gcmTagLength, iv, Uint8List(0)),
      );
    final cipherWithTag = cipher.process(plainBytes);
    return {
      'v': 1,
      'iv': base64.encode(iv),
      'c': base64.encode(cipherWithTag),
    };
  }

  Uint8List? _aesGcmOpen(Uint8List key, Map<String, dynamic> payload) {
    try {
      final iv = Uint8List.fromList(base64.decode(payload['iv'] as String? ?? ''));
      final c = Uint8List.fromList(base64.decode(payload['c'] as String? ?? ''));
      if (iv.length != _gcmIvLength || c.isEmpty) return null;
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(key), _gcmTagLength, iv, Uint8List(0)),
        );
      return cipher.process(c);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>?> createPrivateKeyBackup({
    required String secret,
    int iterations = 200000,
  }) async {
    final privateJwk = await getLocalPrivateKeyJwk();
    final publicJwk = await getLocalPublicKeyJwk();
    if (privateJwk == null || publicJwk == null || secret.trim().isEmpty) return null;
    final salt = Uint8List(16);
    for (var i = 0; i < salt.length; i++) {
      salt[i] = Random.secure().nextInt(256);
    }
    final key = _deriveBackupKey(secret, salt, iterations);
    final sealed = _aesGcmSeal(key, Uint8List.fromList(utf8.encode(privateJwk)));
    return {
      'backup': base64.encode(utf8.encode(jsonEncode(sealed))),
      'salt': base64.encode(salt),
      'iterations': iterations.toString(),
      'publicKey': publicJwk,
    };
  }

  Future<bool> restorePrivateKeyBackup({
    required String backupPayloadB64,
    required String saltB64,
    required int iterations,
    required String secret,
  }) async {
    if (secret.trim().isEmpty) return false;
    try {
      final salt = Uint8List.fromList(base64.decode(saltB64));
      final key = _deriveBackupKey(secret, salt, iterations);
      final payloadJson = utf8.decode(base64.decode(backupPayloadB64));
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
      final plain = _aesGcmOpen(key, payload);
      if (plain == null || plain.isEmpty) return false;
      final privateJwk = utf8.decode(plain);
      await importPrivateKeyJwk(privateJwk);
      return true;
    } catch (_) {
      return false;
    }
  }
}
