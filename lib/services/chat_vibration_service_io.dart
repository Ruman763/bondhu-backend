import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import 'chat_vibration_models.dart';

/// Chat vibration on Android (custom pattern) and iOS (haptics). Load on init; call triggerForNewMessage when a new message notification is shown.
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

  /// Trigger vibration for new message. Android: custom pattern; iOS: haptics.
  Future<void> triggerForNewMessage({String? chatId}) async {
    // Ensure preferences are loaded so enabled/pattern/perChat are correct
    await load();

    if (!enabled.value) return;

    final effectivePattern = patternForChat(chatId);

    if (Platform.isAndroid) {
      try {
        final has = await Vibration.hasVibrator();
        if (has != true) {
          _triggerHaptic(effectivePattern);
          return;
        }
        final durations = effectivePattern.durations;
        final hasCustom = await Vibration.hasCustomVibrationsSupport();
        if (hasCustom == true && durations.length >= 2) {
          // Small delay so vibration isn't dropped when triggered right after notification
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await Vibration.vibrate(pattern: durations);
        } else {
          final ms = durations.length > 1 ? durations[1] : 200;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await Vibration.vibrate(duration: ms);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ChatVibration] Android error: $e');
        }
        _triggerHaptic(effectivePattern);
      }
    } else if (Platform.isIOS) {
      _triggerHaptic(effectivePattern);
    }
  }

  void _triggerHaptic(ChatVibrationPattern p) {
    switch (p) {
      case ChatVibrationPattern.default_:
        HapticFeedback.mediumImpact();
        break;
      case ChatVibrationPattern.doubleTap:
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(milliseconds: 80), () => HapticFeedback.mediumImpact());
        break;
      case ChatVibrationPattern.triple:
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(milliseconds: 60), () {
          HapticFeedback.mediumImpact();
          Future.delayed(const Duration(milliseconds: 60), () => HapticFeedback.mediumImpact());
        });
        break;
      case ChatVibrationPattern.long:
        HapticFeedback.heavyImpact();
        break;
      case ChatVibrationPattern.shortLong:
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(milliseconds: 100), () => HapticFeedback.heavyImpact());
        break;
    }
  }
}
