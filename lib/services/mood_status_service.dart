import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single mood option: label and optional emoji for UI.
class MoodOption {
  const MoodOption(this.key, this.label, this.emoji);
  final String key;
  final String label;
  final String emoji;
}

/// User's current mood/vibe status. Shown in chat header so contacts see "Sarah · Feeling good".
class MoodStatusService {
  MoodStatusService._();
  static final MoodStatusService instance = MoodStatusService._();

  static const String _key = 'bondhu_mood_status';

  static const List<MoodOption> options = [
    MoodOption('', 'None', ''),
    MoodOption('good', 'Feeling good', '😊'),
    MoodOption('happy', 'Happy', '😄'),
    MoodOption('celebrating', 'Celebrating', '🎉'),
    MoodOption('busy', 'Busy', '📌'),
    MoodOption('work', 'At work', '💼'),
    MoodOption('study', 'Studying', '📚'),
    MoodOption('tired', 'Tired', '😴'),
    MoodOption('need_support', 'Need support', '💙'),
    MoodOption('offline', 'Be right back', '⏳'),
  ];

  final ValueNotifier<String> currentMoodKey = ValueNotifier<String>('');

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      currentMoodKey.value = prefs.getString(_key) ?? '';
    } catch (_) {}
  }

  Future<void> setMood(String key) async {
    currentMoodKey.value = key;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (key.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, key);
      }
    } catch (_) {}
  }

  String get displayLabel {
    if (currentMoodKey.value.isEmpty) return '';
    for (final o in options) {
      if (o.key == currentMoodKey.value) return o.label;
    }
    return '';
  }

  String get displayEmoji {
    if (currentMoodKey.value.isEmpty) return '';
    for (final o in options) {
      if (o.key == currentMoodKey.value) return o.emoji;
    }
    return '';
  }

  Future<void> clear() async {
    await setMood('');
  }
}
