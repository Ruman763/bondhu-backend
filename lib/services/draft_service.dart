import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-chat draft text. Persisted in SharedPreferences (or could use EncryptedLocalStore).
class DraftService {
  DraftService._();
  static final DraftService instance = DraftService._();

  static const String _prefix = 'draft_';
  final ValueNotifier<Map<String, String>> drafts = ValueNotifier<Map<String, String>>({});
  Future<SharedPreferences>? _prefsFuture;
  String _accountScope = 'global';

  static String _normAccount(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    return e.isEmpty ? 'global' : e;
  }

  String get _scopedPrefix => '$_prefix${_accountScope}_';

  Future<void> setAccountScope(String? email) async {
    final next = _normAccount(email);
    if (next == _accountScope) return;
    _accountScope = next;
    drafts.value = {};
    await load();
  }

  String _key(String chatId) => '$_scopedPrefix${chatId.trim().toLowerCase()}';

  Future<void> load() async {
    _prefsFuture ??= SharedPreferences.getInstance();
    final prefs = await _prefsFuture!;
    final keys = prefs.getKeys().where((k) => k.startsWith(_scopedPrefix));
    final map = <String, String>{};
    for (final k in keys) {
      final chatId = k.substring(_scopedPrefix.length);
      final v = prefs.getString(k);
      if (v != null && v.isNotEmpty) map[chatId] = v;
    }
    drafts.value = map;
  }

  Future<void> setDraft(String chatId, String text) async {
    final k = _key(chatId);
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    final norm = chatId.trim().toLowerCase();
    if (text.isEmpty) {
      await prefs.remove(k);
      final next = Map<String, String>.from(drafts.value)..remove(norm);
      drafts.value = next;
    } else {
      await prefs.setString(k, text);
      drafts.value = {...drafts.value, norm: text};
    }
  }

  String getDraft(String chatId) {
    return drafts.value[chatId.trim().toLowerCase()] ?? '';
  }

  Future<void> clearDraft(String chatId) async {
    await setDraft(chatId, '');
  }

  Future<void> clearAll() async {
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    final keys = prefs.getKeys().where((k) => k.startsWith(_scopedPrefix)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    drafts.value = {};
  }
}
