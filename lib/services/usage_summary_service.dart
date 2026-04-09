import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional usage summary: track session time in app (for wellbeing / "Time in app this week").
class UsageSummaryService {
  UsageSummaryService._();
  static final UsageSummaryService instance = UsageSummaryService._();

  static const String _keyEnabled = 'usage_summary_enabled';
  static const String _keySessionStart = 'usage_session_start_ms';
  static const String _keyWeekMinutes = 'usage_week_minutes';

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  int _sessionStartMs = 0;
  int _weekMinutes = 0;

  Future<SharedPreferences>? _prefsFuture;

  Future<void> load() async {
    _prefsFuture ??= SharedPreferences.getInstance();
    final prefs = await _prefsFuture!;
    enabled.value = prefs.getBool(_keyEnabled) ?? false;
    _sessionStartMs = prefs.getInt(_keySessionStart) ?? 0;
    _weekMinutes = prefs.getInt(_keyWeekMinutes) ?? 0;
  }

  Future<void> setEnabled(bool on) async {
    final prefs = await (_prefsFuture ?? SharedPreferences.getInstance());
    await prefs.setBool(_keyEnabled, on);
    enabled.value = on;
  }

  /// Call when app comes to foreground.
  Future<void> startSession() async {
    _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
    final prefs = await (_prefsFuture ?? SharedPreferences.getInstance());
    await prefs.setInt(_keySessionStart, _sessionStartMs);
  }

  /// Call when app goes to background; adds session duration to week total.
  Future<void> endSession() async {
    if (_sessionStartMs <= 0) return;
    final elapsed = (DateTime.now().millisecondsSinceEpoch - _sessionStartMs) ~/ 60000;
    _weekMinutes += elapsed;
    _pruneWeekIfNewWeek();
    final prefs = await (_prefsFuture ?? SharedPreferences.getInstance());
    await prefs.setInt(_keyWeekMinutes, _weekMinutes);
    _sessionStartMs = 0;
    await prefs.remove(_keySessionStart);
  }

  void _pruneWeekIfNewWeek() {
    // Simple: store week start in prefs and reset if new week
    // For now just cap at 7*24*60 to avoid unbounded growth
    if (_weekMinutes > 10080) _weekMinutes = 10080;
  }

  /// Total minutes this week (approximate). Call [load] first.
  int get weekMinutes => _weekMinutes;

  String get weekMinutesFormatted {
    if (_weekMinutes < 60) return '$_weekMinutes min';
    final h = _weekMinutes ~/ 60;
    final m = _weekMinutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}
