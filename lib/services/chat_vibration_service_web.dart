import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_vibration_models.dart';

/// No-op on web (no device vibration), but keep same API and persistence for settings and per-chat overrides.
class ChatVibrationService {
  ChatVibrationService._();
  static final ChatVibrationService instance = ChatVibrationService._();

  static const String _keyEnabled = 'chat_vibration_enabled';
  static const String _keyPattern = 'chat_vibration_pattern';
  static const String _keyPerChat = 'chat_vibration_per_chat';

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  final ValueNotifier<ChatVibrationPattern> pattern = ValueNotifier<ChatVibrationPattern>(ChatVibrationPattern.default_);
  final ValueNotifier<Map<String, ChatVibrationPattern>> perChatPatterns =
      ValueNotifier<Map<String, ChatVibrationPattern>>(<String, ChatVibrationPattern>{});

  Future<SharedPreferences>? _prefsFuture;

  Future<void> load() async {
    _prefsFuture ??= SharedPreferences.getInstance();
    final prefs = await _prefsFuture!;
    enabled.value = prefs.getBool(_keyEnabled) ?? true;
    final name = prefs.getString(_keyPattern);
    pattern.value = ChatVibrationPattern.values.firstWhere(
      (p) => p.name == name,
      orElse: () => ChatVibrationPattern.default_,
    );

    final perChatRaw = prefs.getString(_keyPerChat);
    if (perChatRaw != null && perChatRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(perChatRaw) as Map<String, dynamic>;
        final map = <String, ChatVibrationPattern>{};
        decoded.forEach((chatId, value) {
          if (value is String && chatId.isNotEmpty) {
            final pat = ChatVibrationPattern.values.firstWhere(
              (p) => p.name == value,
              orElse: () => ChatVibrationPattern.default_,
            );
            map[chatId] = pat;
          }
        });
        perChatPatterns.value = map;
      } catch (_) {
        perChatPatterns.value = <String, ChatVibrationPattern>{};
      }
    } else {
      perChatPatterns.value = <String, ChatVibrationPattern>{};
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    await prefs.setBool(_keyEnabled, value);
  }

  Future<void> setPattern(ChatVibrationPattern value) async {
    pattern.value = value;
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    await prefs.setString(_keyPattern, value.name);
  }

  ChatVibrationPattern patternForChat(String? chatId) {
    if (chatId == null || chatId.isEmpty) return pattern.value;
    final override = perChatPatterns.value[chatId];
    return override ?? pattern.value;
  }

  Future<void> setChatPattern(String chatId, ChatVibrationPattern? value) async {
    if (chatId.isEmpty) return;
    final current = Map<String, ChatVibrationPattern>.from(perChatPatterns.value);
    if (value == null) {
      current.remove(chatId);
    } else {
      current[chatId] = value;
    }
    perChatPatterns.value = current;
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    final encoded = jsonEncode(
      current.map((key, pat) => MapEntry(key, pat.name)),
    );
    await prefs.setString(_keyPerChat, encoded);
  }

  Future<void> triggerForNewMessage({String? chatId}) async {
    // Web: no device vibration API; still keep API for consistency.
  }
}
