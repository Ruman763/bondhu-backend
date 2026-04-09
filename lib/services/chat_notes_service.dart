import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Folder keys for organizing chat notes.
const String kNoteFolderDefault = 'default';
const String kNoteFolderTodo = 'todo';
const String kNoteFolderImportant = 'important';

/// All folder keys in display order.
const List<String> kNoteFolders = [kNoteFolderDefault, kNoteFolderTodo, kNoteFolderImportant];

/// Shared notepad per chat, with folders (Default, To do, Important). Local only.
class ChatNotesService {
  ChatNotesService._();
  static final ChatNotesService instance = ChatNotesService._();

  static const String _prefix = 'chat_note_';
  /// chatId -> folder -> list of entry texts
  final ValueNotifier<Map<String, Map<String, List<String>>>> notesByFolder = ValueNotifier<Map<String, Map<String, List<String>>>>({});
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
    notesByFolder.value = {};
    await load();
  }

  String _key(String chatId) => '$_scopedPrefix${chatId.trim().toLowerCase()}';

  Future<void> load() async {
    _prefsFuture ??= SharedPreferences.getInstance();
    final prefs = await _prefsFuture!;
    final keys = prefs.getKeys().where((k) => k.startsWith(_scopedPrefix));
    final map = <String, Map<String, List<String>>>{};
    for (final k in keys) {
      final chatId = k.substring(_scopedPrefix.length);
      final v = prefs.getString(k);
      if (v == null || v.isEmpty) continue;
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map<String, dynamic>) {
          final byFolder = <String, List<String>>{};
          for (final entry in decoded.entries) {
            if (entry.value is List) {
              byFolder[entry.key] = (entry.value as List).map((e) => e.toString()).toList();
            }
          }
          map[chatId] = byFolder;
        } else if (decoded is String) {
          // Legacy: single string -> migrate to default folder
          final text = decoded.toString().trim();
          map[chatId] = text.isEmpty ? {} : {kNoteFolderDefault: text.split('\n\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()};
        }
      } catch (_) {
        // Legacy: raw string value (no JSON)
        final text = v.trim();
        map[chatId] = text.isEmpty ? {} : {kNoteFolderDefault: text.split('\n\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()};
      }
    }
    notesByFolder.value = map;
  }

  List<String> _entries(String chatId, String folder) {
    final norm = chatId.trim().toLowerCase();
    final byFolder = notesByFolder.value[norm];
    if (byFolder == null) return [];
    return List.from(byFolder[folder] ?? []);
  }

  /// Entries for one folder (read-only copy).
  List<String> getEntries(String chatId, String folder) => _entries(chatId, folder);

  /// Combined note text for one folder (for backward compat / single blob edit).
  String getNote(String chatId, [String? folder]) {
    final f = folder ?? kNoteFolderDefault;
    return _entries(chatId, f).join('\n\n');
  }

  /// Append a message/line to a folder.
  Future<void> addEntry(String chatId, String folder, String text) async {
    if (text.trim().isEmpty) return;
    await load();
    final norm = chatId.trim().toLowerCase();
    final byFolder = Map<String, List<String>>.from(notesByFolder.value[norm] ?? {});
    final list = List<String>.from(byFolder[folder] ?? []);
    list.add(text.trim());
    byFolder[folder] = list;
    notesByFolder.value = {...notesByFolder.value, norm: byFolder};
    await _save(chatId, byFolder);
  }

  /// Remove entry at index from a folder.
  Future<void> removeEntry(String chatId, String folder, int index) async {
    await load();
    final norm = chatId.trim().toLowerCase();
    final byFolder = Map<String, List<String>>.from(notesByFolder.value[norm] ?? {});
    final list = List<String>.from(byFolder[folder] ?? []);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    if (list.isEmpty) {
      byFolder.remove(folder);
    } else {
      byFolder[folder] = list;
    }
    if (byFolder.isEmpty) {
      notesByFolder.value = Map.from(notesByFolder.value)..remove(norm);
    } else {
      notesByFolder.value = {...notesByFolder.value, norm: byFolder};
    }
    await _save(chatId, byFolder);
  }

  /// Set full note for a folder (replace all entries with lines from text).
  Future<void> setNote(String chatId, String folder, String text) async {
    await load();
    final norm = chatId.trim().toLowerCase();
    final byFolder = Map<String, List<String>>.from(notesByFolder.value[norm] ?? {});
    final lines = text.trim().isEmpty ? <String>[] : text.trim().split('\n\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (lines.isEmpty) {
      byFolder.remove(folder);
    } else {
      byFolder[folder] = lines;
    }
    if (byFolder.isEmpty) {
      notesByFolder.value = Map.from(notesByFolder.value)..remove(norm);
    } else {
      notesByFolder.value = {...notesByFolder.value, norm: byFolder};
    }
    await _save(chatId, byFolder);
  }

  Future<void> _save(String chatId, Map<String, List<String>> byFolder) async {
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    final k = _key(chatId);
    if (byFolder.isEmpty) {
      await prefs.remove(k);
    } else {
      await prefs.setString(k, jsonEncode(byFolder));
    }
  }

  Future<void> clearAll() async {
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    final keys = prefs.getKeys().where((k) => k.startsWith(_scopedPrefix)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    notesByFolder.value = {};
  }
}
