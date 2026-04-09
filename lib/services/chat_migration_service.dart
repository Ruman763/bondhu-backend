import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'supabase_service.dart';
import 'message_sync_crypto_service.dart';

/// WeChat-style migration: old phone uploads a one-time ciphertext; the random
/// token is only in the QR. DB leak does not reveal message keys without the token.
class ChatMigrationService {
  ChatMigrationService._();
  static final ChatMigrationService instance = ChatMigrationService._();

  Uint8List? _decodeBase64UrlSafe(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    try {
      return Uint8List.fromList(base64Url.decode(t));
    } catch (_) {
      try {
        var s = t.replaceAll('-', '+').replaceAll('_', '/');
        final pad = (4 - s.length % 4) % 4;
        s += '=' * pad;
        return Uint8List.fromList(base64.decode(s));
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> ensureKeysForExport() async {
    await MessageSyncCryptoService.instance.ensureMessageVaultKey();
  }

  Future<ChatMigrationQrData?> prepareExport(String accountEmail) async {
    final email = accountEmail.trim().toLowerCase();
    if (email.isEmpty) return null;
    await ensureKeysForExport();
    final keys = await MessageSyncCryptoService.instance.exportKeyMaterialForMigration();
    if (keys.isEmpty) return null;

    final token = Uint8List(32);
    final r = Random.secure();
    for (var i = 0; i < 32; i++) {
      token[i] = r.nextInt(256);
    }
    final inner = jsonEncode(<String, dynamic>{'v': 1, ...keys});
    final sealed = MessageSyncCryptoService.instance.sealMigrationInner(token, inner);
    final docId = await uploadChatMigrationCipher(userId: email, cipher: sealed);
    if (docId == null) return null;
    final tokenStr = base64Url.encode(token);
    final qrJson = jsonEncode(<String, String>{'i': docId, 't': tokenStr});
    return ChatMigrationQrData(documentId: docId, tokenBase64Url: tokenStr, qrPayload: qrJson);
  }

  /// Returns null on success, or an error code for localization.
  Future<String?> applyImport(String accountEmail, String qrRaw) async {
    final email = accountEmail.trim().toLowerCase();
    if (email.isEmpty) return 'migration_invalid_qr';

    Map<String, dynamic> q;
    try {
      q = jsonDecode(qrRaw.trim()) as Map<String, dynamic>;
    } catch (_) {
      return 'migration_invalid_qr';
    }
    final id = q['i'] as String?;
    final t = q['t'] as String?;
    if (id == null || t == null || id.isEmpty || t.isEmpty) return 'migration_invalid_qr';

    Uint8List tokenBytes;
    try {
      tokenBytes = base64Url.decode(t);
    } catch (_) {
      try {
        var s = t.replaceAll('-', '+').replaceAll('_', '/');
        final pad = (4 - s.length % 4) % 4;
        s += '=' * pad;
        tokenBytes = base64.decode(s);
      } catch (_) {
        return 'migration_invalid_qr';
      }
    }
    if (tokenBytes.length != 32) return 'migration_invalid_qr';

    final data = await fetchChatMigrationDoc(id);
    if (data == null) return 'migration_not_found';

    final uid = (data['userId'] as String?)?.trim().toLowerCase();
    if (uid != email) return 'migration_wrong_account';

    final exp = data['expiresAt'] as String?;
    if (exp != null) {
      final at = DateTime.tryParse(exp);
      if (at != null && DateTime.now().toUtc().isAfter(at.toUtc())) {
        await deleteChatMigrationDoc(id);
        return 'migration_expired';
      }
    }

    final cipher = data['cipher'] as String? ?? '';
    if (cipher.isEmpty) return 'migration_bad_payload';

    final plain = MessageSyncCryptoService.instance.unsealMigrationInner(tokenBytes, cipher);
    if (plain == null || plain.isEmpty) return 'migration_decrypt_failed';

    Map<String, dynamic> inner;
    try {
      inner = jsonDecode(plain) as Map<String, dynamic>;
    } catch (_) {
      return 'migration_bad_payload';
    }

    await MessageSyncCryptoService.instance.applyImportedKeyMaterial(inner);
    await deleteChatMigrationDoc(id);
    return null;
  }

  Future<WebLinkQrData?> prepareWebLinkRequest(String accountEmail) async {
    final email = accountEmail.trim().toLowerCase();
    if (email.isEmpty) return null;
    final token = Uint8List(32);
    final r = Random.secure();
    for (var i = 0; i < token.length; i++) {
      token[i] = r.nextInt(256);
    }
    final tokenB64Url = base64Url.encode(token);
    final tokenHash = base64Encode(
      MessageSyncCryptoService.sha256Bytes(Uint8List.fromList(utf8.encode(tokenB64Url))),
    );
    final marker = jsonEncode({
      'mode': 'web_link_req',
      'tokenHash': tokenHash,
      'v': 1,
    });
    final docId = await uploadChatMigrationCipher(userId: email, cipher: marker);
    if (docId == null) return null;
    final qrPayload = jsonEncode(<String, String>{
      'k': 'bondhu-link',
      'i': docId,
      't': tokenB64Url,
    });
    return WebLinkQrData(
      documentId: docId,
      tokenBase64Url: tokenB64Url,
      qrPayload: qrPayload,
    );
  }

  Future<String?> fulfillWebLinkFromPhone(String accountEmail, String qrRaw) async {
    final email = accountEmail.trim().toLowerCase();
    if (email.isEmpty) return 'migration_invalid_qr';
    Map<String, dynamic> q;
    try {
      q = jsonDecode(qrRaw.trim()) as Map<String, dynamic>;
    } catch (_) {
      return 'migration_invalid_qr';
    }
    if ((q['k']?.toString() ?? '') != 'bondhu-link') return 'migration_invalid_qr';
    final id = (q['i']?.toString() ?? '').trim();
    final token = (q['t']?.toString() ?? '').trim();
    if (id.isEmpty || token.isEmpty) return 'migration_invalid_qr';

    final doc = await fetchChatMigrationDoc(id);
    if (doc == null) return 'migration_not_found';
    final uid = (doc['userId'] as String?)?.trim().toLowerCase();
    if (uid != email) return 'migration_wrong_account';

    final cipher = (doc['cipher'] as String?) ?? '';
    Map<String, dynamic> marker;
    try {
      marker = jsonDecode(cipher) as Map<String, dynamic>;
    } catch (_) {
      return 'migration_bad_payload';
    }
    final mode = (marker['mode']?.toString() ?? '').trim();
    if (mode == 'web_link_ready') {
      // Idempotent: already fulfilled by this or another recent scan.
      return null;
    }
    if (mode != 'web_link_req') return 'migration_bad_payload';
    final expectedHash = (marker['tokenHash']?.toString() ?? '').trim();
    final gotHash = base64Encode(
      MessageSyncCryptoService.sha256Bytes(Uint8List.fromList(utf8.encode(token))),
    );
    if (expectedHash.isEmpty || expectedHash != gotHash) return 'migration_decrypt_failed';

    final tokenBytes = _decodeBase64UrlSafe(token);
    if (tokenBytes == null) return 'migration_invalid_qr';
    final keys = await MessageSyncCryptoService.instance.exportKeyMaterialForMigration();
    if (keys.isEmpty) return 'migration_export_failed';
    final inner = jsonEncode(<String, dynamic>{'v': 1, ...keys});
    final sealed = MessageSyncCryptoService.instance.sealMigrationInner(tokenBytes, inner);
    final payload = jsonEncode({
      'mode': 'web_link_ready',
      'payload': sealed,
      'v': 1,
    });
    final ok = await updateChatMigrationCipher(documentId: id, cipher: payload);
    if (!ok) return 'migration_export_failed';
    return null;
  }

  Future<String?> waitAndApplyWebLink({
    required String accountEmail,
    required String documentId,
    required String tokenBase64Url,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final email = accountEmail.trim().toLowerCase();
    if (email.isEmpty || documentId.trim().isEmpty || tokenBase64Url.trim().isEmpty) {
      return 'migration_invalid_qr';
    }
    final started = DateTime.now();
    while (DateTime.now().difference(started) < timeout) {
      final doc = await fetchChatMigrationDoc(documentId);
      if (doc == null) return 'migration_not_found';
      final uid = (doc['userId'] as String?)?.trim().toLowerCase();
      if (uid != email) return 'migration_wrong_account';
      final cipher = (doc['cipher'] as String?) ?? '';
      if (cipher.isNotEmpty) {
        try {
          final json = jsonDecode(cipher) as Map<String, dynamic>;
          if ((json['mode']?.toString() ?? '') == 'web_link_ready') {
            final sealed = (json['payload']?.toString() ?? '').trim();
            if (sealed.isEmpty) return 'migration_bad_payload';
            final tokenBytes = _decodeBase64UrlSafe(tokenBase64Url);
            if (tokenBytes == null) return 'migration_invalid_qr';
            final plain = MessageSyncCryptoService.instance.unsealMigrationInner(tokenBytes, sealed);
            if (plain == null || plain.isEmpty) return 'migration_decrypt_failed';
            final inner = jsonDecode(plain) as Map<String, dynamic>;
            await MessageSyncCryptoService.instance.applyImportedKeyMaterial(inner);
            await deleteChatMigrationDoc(documentId);
            return null;
          }
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    // Timeout: remove stale one-time request so user gets a clean retry.
    await deleteChatMigrationDoc(documentId);
    return 'migration_timeout';
  }
}

class ChatMigrationQrData {
  ChatMigrationQrData({
    required this.documentId,
    required this.tokenBase64Url,
    required this.qrPayload,
  });

  final String documentId;
  final String tokenBase64Url;
  /// JSON string to encode in the QR image.
  final String qrPayload;
}

class WebLinkQrData {
  WebLinkQrData({
    required this.documentId,
    required this.tokenBase64Url,
    required this.qrPayload,
  });

  final String documentId;
  final String tokenBase64Url;
  final String qrPayload;
}
