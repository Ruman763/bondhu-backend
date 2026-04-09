import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A message scheduled to be sent at [sendAtMs].
class ScheduledMessage {
  const ScheduledMessage({
    required this.id,
    required this.chatId,
    required this.text,
    required this.sendAtMs,
    this.type = 'text',
    this.replyToId,
    this.replyToText,
  });

  final String id;
  final String chatId;
  final String text;
  final int sendAtMs;
  final String type;
  final String? replyToId;
  final String? replyToText;

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'text': text,
        'sendAtMs': sendAtMs,
        'type': type,
        'replyToId': replyToId,
        'replyToText': replyToText,
      };

  static ScheduledMessage fromJson(Map<String, dynamic> j) => ScheduledMessage(
        id: j['id'] as String? ?? '',
        chatId: j['chatId'] as String? ?? '',
        text: j['text'] as String? ?? '',
        sendAtMs: (j['sendAtMs'] as num?)?.toInt() ?? 0,
        type: j['type'] as String? ?? 'text',
        replyToId: j['replyToId'] as String?,
        replyToText: j['replyToText'] as String?,
      );
}

/// Persists scheduled messages and fires at [sendAtMs]. Call [startTimer] after init.
class ScheduleMessageService {
  ScheduleMessageService._();
  static final ScheduleMessageService instance = ScheduleMessageService._();

  static const String _key = 'schedule_messages';
  final ValueNotifier<List<ScheduledMessage>> scheduled = ValueNotifier<List<ScheduledMessage>>([]);
  Timer? _timer;
  Future<SharedPreferences>? _prefsFuture;
  void Function(String chatId, String text, String type, {String? replyToId, String? replyToText})? onSendScheduled;

  Future<void> load() async {
    _prefsFuture ??= SharedPreferences.getInstance();
    final prefs = await _prefsFuture!;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      scheduled.value = [];
      return;
    }
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => ScheduledMessage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      scheduled.value = list;
    } catch (_) {
      scheduled.value = [];
    }
  }

  Future<void> _save() async {
    final prefs = await (_prefsFuture ??= SharedPreferences.getInstance());
    await prefs.setString(_key, jsonEncode(scheduled.value.map((e) => e.toJson()).toList()));
  }

  /// Add a scheduled message. Call [startTimer] if not already running.
  Future<void> add(ScheduledMessage msg) async {
    await load();
    if (scheduled.value.any((e) => e.id == msg.id)) return;
    scheduled.value = [...scheduled.value, msg];
    await _save();
    _scheduleNext();
  }

  /// Remove by id.
  Future<void> remove(String id) async {
    await load();
    scheduled.value = scheduled.value.where((e) => e.id != id).toList();
    await _save();
  }

  List<ScheduledMessage> forChat(String chatId) {
    final norm = chatId.trim().toLowerCase();
    return scheduled.value.where((e) => e.chatId.trim().toLowerCase() == norm).toList();
  }

  void startTimer() {
    _timer?.cancel();
    void check() async {
      await load();
      final now = DateTime.now().millisecondsSinceEpoch;
      final toSend = scheduled.value.where((e) => e.sendAtMs <= now).toList();
      for (final msg in toSend) {
        onSendScheduled?.call(
          msg.chatId,
          msg.text,
          msg.type,
          replyToId: msg.replyToId,
          replyToText: msg.replyToText,
        );
        await remove(msg.id);
      }
      _scheduleNext();
    }

    check();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => check());
  }

  void _scheduleNext() {
    // Timer is already periodic; no need to schedule one-off
  }

  void dispose() {
    _timer?.cancel();
  }
}
