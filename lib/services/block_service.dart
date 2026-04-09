import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import 'encrypted_local_store.dart';

/// Persisted list of blocked user IDs (emails). Used to hide chats and filter search.
class BlockService {
  BlockService._();
  static final BlockService instance = BlockService._();

  static const String _storageKey = 'bondhu_blocked_ids';

  final List<String> _ids = [];
  final ValueNotifier<List<String>> blockedIdsNotifier = ValueNotifier<List<String>>([]);

  List<String> get blockedIds => List.unmodifiable(_ids);

  bool isBlocked(String? userId) {
    if (userId == null || userId.isEmpty) return false;
    final norm = userId.trim().toLowerCase();
    return _ids.any((id) => id.trim().toLowerCase() == norm);
  }

  Future<void> _load() async {
    try {
      String? json;
      if (EncryptedLocalStore.instance.isReady) {
        json = await EncryptedLocalStore.instance.getString(_storageKey);
      }
      if (json == null || json.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        json = prefs.getString(_storageKey);
      }
      _ids.clear();
      if (json != null && json.isNotEmpty) {
        final list = jsonDecode(json) as List<dynamic>?;
        if (list != null) {
          for (final e in list) {
            if (e != null && e.toString().trim().isNotEmpty) {
              _ids.add(e.toString().trim().toLowerCase());
            }
          }
        }
      }
      blockedIdsNotifier.value = List.from(_ids);
    } catch (e) {
      if (kDebugMode) debugPrint('[BlockService] _load error: $e');
    }
  }

  Future<void> _save() async {
    try {
      final json = jsonEncode(_ids);
      if (EncryptedLocalStore.instance.isReady) {
        await EncryptedLocalStore.instance.setString(_storageKey, json);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_storageKey, json);
      }
      blockedIdsNotifier.value = List.from(_ids);
    } catch (e) {
      if (kDebugMode) debugPrint('[BlockService] _save error: $e');
    }
  }

  /// Call once at app start (e.g. from HomeShell or main).
  Future<void> init() async {
    await _load();
  }

  /// Clear all blocked IDs (e.g. when switching accounts).
  Future<void> clearAll() async {
    _ids.clear();
    blockedIdsNotifier.value = [];
    try {
      if (EncryptedLocalStore.instance.isReady) {
        await EncryptedLocalStore.instance.remove(_storageKey);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      if (kDebugMode) debugPrint('[BlockService] clearAll error: $e');
    }
  }

  Future<void> add(String userId) async {
    final norm = userId.trim().toLowerCase();
    if (norm.isEmpty) return;
    if (_ids.any((id) => id == norm)) return;
    _ids.add(norm);
    await _save();
  }

  Future<void> remove(String userId) async {
    final norm = userId.trim().toLowerCase();
    _ids.removeWhere((id) => id == norm);
    await _save();
  }
}
