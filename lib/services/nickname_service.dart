import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_service.dart';

/// Per-chat nicknames that only you see. Stored locally; not sent to server.
class NicknameService {
  NicknameService._();
  static final NicknameService instance = NicknameService._();

  static const String _key = 'bondhu_nicknames';
  final ValueNotifier<Map<String, String>> nicknames = ValueNotifier<Map<String, String>>({});
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key);
      if (json != null && json.isNotEmpty) {
        final map = jsonDecode(json) as Map<String, dynamic>?;
        if (map != null) {
          nicknames.value = map.map((k, v) => MapEntry(k, v as String));
        }
      }
      _loaded = true;
    } catch (_) {}
  }

  /// Call early (e.g. from chat list) so nicknames are available.
  Future<void> load() async => _ensureLoaded();

  /// Display name for a chat: nickname if set, otherwise chat.name.
  String getDisplayName(ChatItem chat) {
    final n = nicknames.value[chat.id];
    if (n != null && n.trim().isNotEmpty) return n.trim();
    return chat.name;
  }

  String? getNickname(String chatId) => nicknames.value[chatId];

  Future<void> setNickname(String chatId, String? name) async {
    await _ensureLoaded();
    final next = Map<String, String>.from(nicknames.value);
    if (name == null || name.trim().isEmpty) {
      next.remove(chatId);
    } else {
      next[chatId] = name.trim();
    }
    nicknames.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(next));
    } catch (_) {}
  }

  Future<void> clearAll() async {
    nicknames.value = {};
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
