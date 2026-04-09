import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';

/// Per-friend custom voice and video messages played to the caller when the user
/// (callee) does not answer. Stored as URLs (e.g. Supabase Storage) so the caller can play them.
class CustomCallMessageService {
  CustomCallMessageService._();
  static final CustomCallMessageService instance = CustomCallMessageService._();

  static const String _keyPrefix = 'custom_call_message_';
  String _accountScope = 'global';

  static String _normAccount(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    return e.isEmpty ? 'global' : e;
  }

  Future<void> setAccountScope(String? email) async {
    _accountScope = _normAccount(email);
  }

  String _key(String chatId) => '$_keyPrefix${_accountScope}_${chatId.trim().toLowerCase()}';

  /// Get the voice message URL for [chatId], or null if not set.
  Future<String?> getVoiceMessageUrl(String chatId) async {
    if (chatId.trim().isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key(chatId));
      if (json == null) return null;
      final map = jsonDecode(json) as Map<String, dynamic>?;
      return map?['voiceMessageUrl']?.toString();
    } catch (e) {
      if (kDebugMode) debugPrint('[CustomCallMessageService] getVoiceMessageUrl error: $e');
      return null;
    }
  }

  /// Get the video message URL for [chatId], or null if not set.
  Future<String?> getVideoMessageUrl(String chatId) async {
    if (chatId.trim().isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key(chatId));
      if (json == null) return null;
      final map = jsonDecode(json) as Map<String, dynamic>?;
      return map?['videoMessageUrl']?.toString();
    } catch (e) {
      if (kDebugMode) debugPrint('[CustomCallMessageService] getVideoMessageUrl error: $e');
      return null;
    }
  }

  /// Set voice message URL for [chatId]. Pass null or empty to clear.
  Future<void> setVoiceMessage(String chatId, String? url) async {
    if (chatId.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(chatId);
      final existing = prefs.getString(key);
      final map = existing != null
          ? (jsonDecode(existing) as Map<String, dynamic>? ?? <String, dynamic>{})
          : <String, dynamic>{};
      if (url == null || url.trim().isEmpty) {
        map.remove('voiceMessageUrl');
      } else {
        map['voiceMessageUrl'] = url.trim();
      }
      if (map.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode(map));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CustomCallMessageService] setVoiceMessage error: $e');
    }
  }

  /// Set video message URL for [chatId]. Pass null or empty to clear.
  Future<void> setVideoMessage(String chatId, String? url) async {
    if (chatId.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _key(chatId);
      final existing = prefs.getString(key);
      final map = existing != null
          ? (jsonDecode(existing) as Map<String, dynamic>? ?? <String, dynamic>{})
          : <String, dynamic>{};
      if (url == null || url.trim().isEmpty) {
        map.remove('videoMessageUrl');
      } else {
        map['videoMessageUrl'] = url.trim();
      }
      if (map.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode(map));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CustomCallMessageService] setVideoMessage error: $e');
    }
  }

  /// Clear both voice and video messages for [chatId].
  Future<void> clearAll(String chatId) async {
    if (chatId.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(chatId));
    } catch (e) {
      if (kDebugMode) debugPrint('[CustomCallMessageService] clearAll error: $e');
    }
  }
}
