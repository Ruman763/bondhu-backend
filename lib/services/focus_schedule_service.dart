import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Focus / DND schedule: quiet hours and optional auto-reply.
class FocusScheduleService {
  FocusScheduleService._();
  static final FocusScheduleService instance = FocusScheduleService._();

  static const String _keyEnabled = 'focus_enabled';
  static const String _keyStartHour = 'focus_start_hour';
  static const String _keyStartMinute = 'focus_start_minute';
  static const String _keyEndHour = 'focus_end_hour';
  static const String _keyEndMinute = 'focus_end_minute';
  static const String _keyAutoReply = 'focus_auto_reply';

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<int> startHour = ValueNotifier<int>(22); // 10 PM
  final ValueNotifier<int> startMinute = ValueNotifier<int>(0);
  final ValueNotifier<int> endHour = ValueNotifier<int>(8); // 8 AM
  final ValueNotifier<int> endMinute = ValueNotifier<int>(0);
  final ValueNotifier<String> autoReplyText = ValueNotifier<String>('');

  Future<SharedPreferences>? _prefsFuture;

  Future<void> load() async {
    _prefsFuture ??= SharedPreferences.getInstance();
    final prefs = await _prefsFuture!;
    enabled.value = prefs.getBool(_keyEnabled) ?? false;
    startHour.value = prefs.getInt(_keyStartHour) ?? 22;
    startMinute.value = prefs.getInt(_keyStartMinute) ?? 0;
    endHour.value = prefs.getInt(_keyEndHour) ?? 8;
    endMinute.value = prefs.getInt(_keyEndMinute) ?? 0;
    autoReplyText.value = prefs.getString(_keyAutoReply) ?? '';
  }

  Future<void> setEnabled(bool on) async {
    final prefs = await (_prefsFuture ?? SharedPreferences.getInstance());
    await prefs.setBool(_keyEnabled, on);
    enabled.value = on;
  }

  Future<void> setSchedule(int startH, int startM, int endH, int endM) async {
    final prefs = await (_prefsFuture ?? SharedPreferences.getInstance());
    await prefs.setInt(_keyStartHour, startH);
    await prefs.setInt(_keyStartMinute, startM);
    await prefs.setInt(_keyEndHour, endH);
    await prefs.setInt(_keyEndMinute, endM);
    startHour.value = startH;
    startMinute.value = startM;
    endHour.value = endH;
    endMinute.value = endM;
  }

  Future<void> setAutoReply(String text) async {
    final prefs = await (_prefsFuture ?? SharedPreferences.getInstance());
    await prefs.setString(_keyAutoReply, text);
    autoReplyText.value = text;
  }

  /// True if we're currently inside focus (DND) window.
  bool get isInFocusWindow {
    if (!enabled.value) return false;
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    int start = startHour.value * 60 + startMinute.value;
    int end = endHour.value * 60 + endMinute.value;
    if (start <= end) {
      return nowMinutes >= start && nowMinutes < end;
    }
    return nowMinutes >= start || nowMinutes < end;
  }
}
