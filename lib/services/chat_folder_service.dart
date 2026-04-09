import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Folder labels for organizing chats (e.g. Work, Family, Groups).
class ChatFolderService {
  ChatFolderService._();
  static final ChatFolderService instance = ChatFolderService._();

  static const String _keyMap = 'chat_folders';
  final ValueNotifier<Map<String, String>> chatToFolder = ValueNotifier<Map<String, String>>({});
  Future<SharedPreferences>? _prefsFuture;

  Future<void> load() async {
    _prefsFuture ??= SharedPreferences.getInstance();
    final prefs = await _prefsFuture!;
    final raw = prefs.getString(_keyMap);
    if (raw == null || raw.isEmpty) {
      chatToFolder.value = {};
      return;
    }
    try {
      final map = (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
      chatToFolder.value = map;
    } catch (_) {
      chatToFolder.value = {};
    }
  }

  Future<void> _save() async {
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    await prefs.setString(_keyMap, jsonEncode(chatToFolder.value));
  }

  String? getFolder(String chatId) => chatToFolder.value[chatId.trim().toLowerCase()];

  Future<void> setFolder(String chatId, String? folderName) async {
    await load();
    final norm = chatId.trim().toLowerCase();
    if (folderName == null || folderName.trim().isEmpty) {
      chatToFolder.value = Map.from(chatToFolder.value)..remove(norm);
    } else {
      chatToFolder.value = {...chatToFolder.value, norm: folderName.trim()};
    }
    await _save();
  }

  /// All folder names in use.
  List<String> get allFolders {
    final set = chatToFolder.value.values.toSet();
    final list = set.toList()..sort();
    return list;
  }
}
