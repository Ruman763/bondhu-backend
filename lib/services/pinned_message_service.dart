import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Max pinned messages per chat (like WhatsApp).
const int kMaxPinnedPerChat = 3;

/// Per-chat pinned message IDs. Persisted in SharedPreferences.
class PinnedMessageService {
  PinnedMessageService._();
  static final PinnedMessageService instance = PinnedMessageService._();

  static const String _prefix = 'pinned_msgs_';
  final ValueNotifier<int> version = ValueNotifier<int>(0);
  Map<String, List<String>> _cache = {};
  Future<SharedPreferences>? _prefsFuture;

  String _key(String chatId) => '$_prefix${chatId.trim().toLowerCase()}';

  Future<void> load() async {
    _prefsFuture ??= SharedPreferences.getInstance();
    final prefs = await _prefsFuture!;
    _cache = {};
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final k in keys) {
      final raw = prefs.getString(k);
      if (raw == null) continue;
      try {
        final list = (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toList();
        _cache[k] = list;
      } catch (_) {}
    }
    version.value++;
  }

  Future<void> _save(String chatId) async {
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    final list = _cache[_key(chatId)] ?? [];
    await prefs.setString(_key(chatId), jsonEncode(list));
    version.value++;
  }

  /// Pinned message IDs for [chatId] (order preserved).
  List<String> getPinned(String chatId) {
    final k = _key(chatId);
    return List.from(_cache[k] ?? []);
  }

  bool isPinned(String chatId, String messageId) {
    return getPinned(chatId).contains(messageId);
  }

  /// Pin a message. Returns false if already at max.
  Future<bool> pin(String chatId, String messageId) async {
    await load();
    final k = _key(chatId);
    var list = List<String>.from(_cache[k] ?? []);
    if (list.contains(messageId)) return true;
    if (list.length >= kMaxPinnedPerChat) return false;
    list.add(messageId);
    _cache[k] = list;
    await _save(chatId);
    return true;
  }

  /// Unpin a message.
  Future<void> unpin(String chatId, String messageId) async {
    await load();
    final k = _key(chatId);
    var list = List<String>.from(_cache[k] ?? []);
    list.remove(messageId);
    _cache[k] = list;
    await _save(chatId);
  }
}
