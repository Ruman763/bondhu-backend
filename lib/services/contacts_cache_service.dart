import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'supabase_service.dart';
import 'encrypted_local_store.dart';

/// Offline-first cache for contacts.
/// - Fast startup: read from encrypted local store.
/// - Cross-device consistency: refreshed from backend by callers.
class ContactsCacheService {
  ContactsCacheService._();
  static final ContactsCacheService instance = ContactsCacheService._();

  static String _keyForUser(String userId) => 'contacts_cache_${userId.trim().toLowerCase()}';

  Future<List<ProfileDoc>> read(String userId) async {
    if (userId.trim().isEmpty || !EncryptedLocalStore.instance.isReady) return const [];
    try {
      final raw = await EncryptedLocalStore.instance.getString(_keyForUser(userId));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <ProfileDoc>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final profileUserId = (m['userId']?.toString() ?? '').trim().toLowerCase();
        if (profileUserId.isEmpty) continue;
        out.add(
          ProfileDoc(
            docId: m['docId']?.toString() ?? '',
            userId: profileUserId,
            name: (m['name']?.toString() ?? profileUserId.split('@').first),
            avatar: (m['avatar']?.toString() ?? '').trim().isNotEmpty
                ? m['avatar'].toString()
                : defaultAvatar(profileUserId),
            bio: m['bio']?.toString(),
            location: m['location']?.toString(),
          ),
        );
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('[ContactsCacheService] read failed: $e');
      return const [];
    }
  }

  Future<void> write(String userId, List<ProfileDoc> contacts) async {
    if (userId.trim().isEmpty || !EncryptedLocalStore.instance.isReady) return;
    try {
      final data = contacts
          .map((p) => <String, dynamic>{
                'docId': p.docId,
                'userId': p.userId,
                'name': p.name,
                'avatar': p.avatar,
                'bio': p.bio,
                'location': p.location,
              })
          .toList();
      await EncryptedLocalStore.instance.setString(_keyForUser(userId), jsonEncode(data));
    } catch (e) {
      if (kDebugMode) debugPrint('[ContactsCacheService] write failed: $e');
    }
  }
}
