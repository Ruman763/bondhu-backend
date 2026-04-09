import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reply-later reminder: chatId, messageId, reminder time, and preview text.
class ReplyLaterReminder {
  const ReplyLaterReminder({
    required this.chatId,
    required this.messageId,
    required this.remindAtMs,
    required this.previewText,
    this.chatName,
  });

  final String chatId;
  final String messageId;
  final int remindAtMs;
  final String previewText;
  final String? chatName;

  Map<String, dynamic> toJson() => {
        'chatId': chatId,
        'messageId': messageId,
        'remindAtMs': remindAtMs,
        'previewText': previewText,
        'chatName': chatName,
      };

  static ReplyLaterReminder? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final chatId = j['chatId'] as String?;
    final messageId = j['messageId'] as String?;
    final remindAtMs = j['remindAtMs'] as int?;
    final previewText = j['previewText'] as String?;
    if (chatId == null || messageId == null || remindAtMs == null || previewText == null) return null;
    return ReplyLaterReminder(
      chatId: chatId,
      messageId: messageId,
      remindAtMs: remindAtMs,
      previewText: previewText,
      chatName: j['chatName'] as String?,
    );
  }
}

/// Store and retrieve "reply later" reminders. Notifications/scheduling can be added separately.
class ReplyLaterService {
  ReplyLaterService._();
  static final ReplyLaterService instance = ReplyLaterService._();

  static const String _key = 'bondhu_reply_later';

  /// Human-readable time for a reminder (e.g. "Due now", "In 2 hours", "Tomorrow 9 AM").
  static String formatWhen(int remindAtMs) {
    final now = DateTime.now();
    final then = DateTime.fromMillisecondsSinceEpoch(remindAtMs);
    final diff = then.difference(now);
    if (diff.inMinutes <= 0) return 'Due now';
    if (diff.inMinutes < 60) return 'In ${diff.inMinutes} min';
    if (diff.inHours < 24 && then.day == now.day) return 'In ${diff.inHours} hr';
    final tomorrow = now.add(const Duration(days: 1));
    if (then.year == tomorrow.year && then.month == tomorrow.month && then.day == tomorrow.day) {
      return 'Tomorrow ${then.hour.toString().padLeft(2, '0')}:${then.minute.toString().padLeft(2, '0')}';
    }
    return '${then.day}/${then.month} ${then.hour.toString().padLeft(2, '0')}:${then.minute.toString().padLeft(2, '0')}';
  }
  final ValueNotifier<List<ReplyLaterReminder>> reminders = ValueNotifier<List<ReplyLaterReminder>>([]);
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_key);
      if (json != null && json.isNotEmpty) {
        final list = jsonDecode(json) as List<dynamic>?;
        if (list != null) {
          reminders.value = list
              .map((e) => ReplyLaterReminder.fromJson(e as Map<String, dynamic>?))
              .whereType<ReplyLaterReminder>()
              .toList();
        }
      }
      _loaded = true;
    } catch (_) {}
  }

  /// Call so reminders are loaded from storage (e.g. before showing the list).
  Future<void> load() async => _ensureLoaded();

  Future<void> add(ReplyLaterReminder r) async {
    await _ensureLoaded();
    final next = List<ReplyLaterReminder>.from(reminders.value)..add(r);
    next.sort((a, b) => a.remindAtMs.compareTo(b.remindAtMs));
    reminders.value = next;
    await _save(next);
  }

  Future<void> remove(String chatId, String messageId) async {
    await _ensureLoaded();
    reminders.value = reminders.value
        .where((r) => !(r.chatId == chatId && r.messageId == messageId))
        .toList();
    await _save(reminders.value);
  }

  List<ReplyLaterReminder> get dueNow {
    final now = DateTime.now().millisecondsSinceEpoch;
    return reminders.value.where((r) => r.remindAtMs <= now).toList();
  }

  List<ReplyLaterReminder> get upcoming {
    final now = DateTime.now().millisecondsSinceEpoch;
    return reminders.value.where((r) => r.remindAtMs > now).toList();
  }

  Future<void> _save(List<ReplyLaterReminder> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> clearAll() async {
    reminders.value = [];
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
