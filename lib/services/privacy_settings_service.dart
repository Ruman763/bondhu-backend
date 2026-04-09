import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User toggles for read receipts, last seen, online status, typing indicator.
/// Single source of truth for presence/privacy; used by ChatService when emitting to server.
class PrivacySettingsService {
  PrivacySettingsService._();
  static final PrivacySettingsService instance = PrivacySettingsService._();

  static const String _keyReadReceipts = 'privacy_read_receipts';
  static const String _keyLastSeen = 'privacy_last_seen';
  static const String _keyShowOnline = 'privacy_show_online';
  static const String _keyTypingIndicator = 'privacy_typing_indicator';

  final ValueNotifier<bool> readReceiptsOn = ValueNotifier<bool>(true);
  final ValueNotifier<bool> lastSeenOn = ValueNotifier<bool>(true);
  final ValueNotifier<bool> showOnlineStatusOn = ValueNotifier<bool>(true);
  final ValueNotifier<bool> typingIndicatorOn = ValueNotifier<bool>(true);

  Future<SharedPreferences>? _prefsFuture;

  Future<void> load() async {
    _prefsFuture ??= SharedPreferences.getInstance();
    final prefs = await _prefsFuture!;
    readReceiptsOn.value = prefs.getBool(_keyReadReceipts) ?? true;
    lastSeenOn.value = prefs.getBool(_keyLastSeen) ?? true;
    showOnlineStatusOn.value = prefs.getBool(_keyShowOnline) ?? true;
    typingIndicatorOn.value = prefs.getBool(_keyTypingIndicator) ?? true;
  }

  Future<void> setReadReceipts(bool on) async {
    final prefs = await (_prefsFuture ?? SharedPreferences.getInstance());
    await prefs.setBool(_keyReadReceipts, on);
    readReceiptsOn.value = on;
  }

  Future<void> setLastSeen(bool on) async {
    final prefs = await (_prefsFuture ?? SharedPreferences.getInstance());
    await prefs.setBool(_keyLastSeen, on);
    lastSeenOn.value = on;
  }

  Future<void> setShowOnlineStatus(bool on) async {
    final prefs = await (_prefsFuture ?? SharedPreferences.getInstance());
    await prefs.setBool(_keyShowOnline, on);
    showOnlineStatusOn.value = on;
  }

  Future<void> setTypingIndicator(bool on) async {
    final prefs = await (_prefsFuture ?? SharedPreferences.getInstance());
    await prefs.setBool(_keyTypingIndicator, on);
    typingIndicatorOn.value = on;
  }
}
