import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, ValueListenable, ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import 'encrypted_local_store.dart';

/// One starred message entry: chatId, messageId, optional label (e.g. "Important", "To do").
class StarredEntry {
  const StarredEntry({
    required this.chatId,
    required this.messageId,
    this.label,
  });

  final String chatId;
  final String messageId;
  final String? label;

  Map<String, dynamic> toJson() => {
        'chatId': chatId,
        'messageId': messageId,
        'label': label,
      };

  static StarredEntry fromJson(Map<String, dynamic> j) => StarredEntry(
        chatId: j['chatId'] as String? ?? '',
        messageId: j['messageId'] as String? ?? '',
        label: j['label'] as String?,
      );
}

/// Persists and notifies starred messages. Better than WhatsApp: optional labels (Important, To do, Later).
class StarredMessageService {
  StarredMessageService._();
  static final StarredMessageService _instance = StarredMessageService._();
  static StarredMessageService get instance => _instance;

  static const String _storageKey = 'bondhu_starred';
  final List<StarredEntry> _list = [];
  final ValueNotifier<int> _version = ValueNotifier<int>(0);

  ValueListenable<int> get version => _version;

  /// All starred entries (chatId, messageId, label). Order: most recently starred first.
  List<StarredEntry> get all => List.unmodifiable(_list);

  bool isStarred(String chatId, String messageId) {
    final c = chatId.trim().toLowerCase();
    final m = messageId.trim();
    return _list.any((e) => e.chatId.toLowerCase() == c && e.messageId == m);
  }

  String? getLabel(String chatId, String messageId) {
    final c = chatId.trim().toLowerCase();
    final m = messageId.trim();
    for (final e in _list) {
      if (e.chatId.toLowerCase() == c && e.messageId == m) return e.label;
    }
    return null;
  }

  /// Add or update star. [label] optional (e.g. "Important", "To do", "Later").
  Future<void> add(String chatId, String messageId, {String? label}) async {
    remove(chatId, messageId);
    _list.insert(0, StarredEntry(chatId: chatId, messageId: messageId, label: label));
    await _save();
    _version.value++;
  }

  Future<void> remove(String chatId, String messageId) async {
    final c = chatId.trim().toLowerCase();
    final m = messageId.trim();
    _list.removeWhere((e) => e.chatId.toLowerCase() == c && e.messageId == m);
    await _save();
    _version.value++;
  }

  Future<void> _save() async {
    try {
      final json = jsonEncode(_list.map((e) => e.toJson()).toList());
      try {
        await EncryptedLocalStore.instance.setString(_storageKey, json);
      } catch (_) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_storageKey, json);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[StarredMessageService] _save error: $e');
    }
  }

  Future<void> load() async {
    try {
      String? json;
      try {
        json = await EncryptedLocalStore.instance.getString(_storageKey);
      } catch (_) {}
      json ??= (await SharedPreferences.getInstance()).getString(_storageKey);
      _list.clear();
      if (json != null && json.isNotEmpty) {
        final decoded = jsonDecode(json) as List<dynamic>?;
        if (decoded != null) {
          for (final e in decoded) {
            if (e is Map<String, dynamic>) _list.add(StarredEntry.fromJson(e));
          }
        }
      }
      _version.value++;
    } catch (e) {
      if (kDebugMode) debugPrint('[StarredMessageService] load error: $e');
    }
  }
}
