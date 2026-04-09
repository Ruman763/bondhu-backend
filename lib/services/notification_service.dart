import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hidden_chats_service.dart';
import 'app_language_service.dart';

/// In-app notification item.
class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.avatarUrl,
    required this.time,
    this.read = false,
    this.chatId,
    this.extra,
  });

  final String id;
  final String type; // message, like, comment, follow, story_view, system
  final String title;
  final String body;
  final String? avatarUrl;
  final DateTime time;
  final bool read;
  final String? chatId;
  final Map<String, dynamic>? extra;

  AppNotification copyWith({
    String? id,
    String? type,
    String? title,
    String? body,
    String? avatarUrl,
    DateTime? time,
    bool? read,
    String? chatId,
    Map<String, dynamic>? extra,
  }) =>
      AppNotification(
        id: id ?? this.id,
        type: type ?? this.type,
        title: title ?? this.title,
        body: body ?? this.body,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        time: time ?? this.time,
        read: read ?? this.read,
        chatId: chatId ?? this.chatId,
        extra: extra ?? this.extra,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'body': body,
        'avatarUrl': avatarUrl,
        'time': time.toIso8601String(),
        'read': read,
        'chatId': chatId,
        if (extra != null) 'extra': extra,
      };

  static AppNotification fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String? ?? '',
        type: j['type'] as String? ?? 'system',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        time: DateTime.tryParse(j['time'] as String? ?? '') ?? DateTime.now(),
        read: j['read'] as bool? ?? false,
        chatId: j['chatId'] as String?,
        extra: j['extra'] as Map<String, dynamic>?,
      );
}

/// In-app notification center: store, persist, and expose notifications + unread count.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String _storageKey = 'bondhu_notifications';
  static const int _maxNotifications = 200;
  String _accountScope = 'global';

  static String _normAccount(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    return e.isEmpty ? 'global' : e;
  }

  String get _scopedStorageKey => '${_storageKey}_$_accountScope';

  final List<AppNotification> _list = [];
  final _controller = StreamController<List<AppNotification>>.broadcast();

  List<AppNotification> get list => List.unmodifiable(_list);
  Stream<List<AppNotification>> get stream => _controller.stream;
  int get unreadCount => _list.where((n) => !n.read).length;

  /// Separate notification cache per account on same device.
  /// Call this before load() when user session changes.
  Future<void> setAccountScope(String? email) async {
    final next = _normAccount(email);
    if (next == _accountScope) return;
    _accountScope = next;
    _list.clear();
    _notify();
    await load();
  }

  /// Call when a new message arrives and user is not on that chat.
  void addMessageNotification({
    required String chatId,
    required String chatName,
    required String messageText,
    String? avatarUrl,
  }) {
    final isHidden = HiddenChatsService.instance.isHidden(chatId);
    final now = DateTime.now();
    if (isHidden) {
      // For hidden chats, keep notifications discreet: no chat name or message preview.
      final t = AppLanguageService.instance.t;
      add(
        AppNotification(
          id: 'msg_${chatId}_${now.millisecondsSinceEpoch}',
          type: 'message',
          title: t('hidden_chat_notification_title'),
          body: t('hidden_chat_notification_body'),
          avatarUrl: null,
          time: now,
          read: false,
          chatId: chatId,
        ),
      );
    } else {
      final preview = messageText.length > 60 ? '${messageText.substring(0, 60)}...' : messageText;
      add(
        AppNotification(
          id: 'msg_${chatId}_${now.millisecondsSinceEpoch}',
          type: 'message',
          title: chatName,
          body: preview,
          avatarUrl: avatarUrl,
          time: now,
          read: false,
          chatId: chatId,
        ),
      );
    }
    // Vibration is handled in ChatService at real receive-time so per-chat vibration
    // also works while app is open in foreground.
  }

  void addSystemNotification({required String title, required String body}) {
    add(AppNotification(
      id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
      type: 'system',
      title: title,
      body: body,
      time: DateTime.now(),
      read: false,
    ));
  }

  void add(AppNotification n) {
    _list.insert(0, n);
    while (_list.length > _maxNotifications) {
      _list.removeLast();
    }
    _save();
    _notify();
  }

  void markRead(String id) {
    final i = _list.indexWhere((n) => n.id == id);
    if (i >= 0 && !_list[i].read) {
      _list[i] = _list[i].copyWith(read: true);
      _save();
      _notify();
    }
  }

  void markAllRead() {
    bool changed = false;
    for (var i = 0; i < _list.length; i++) {
      if (!_list[i].read) {
        _list[i] = _list[i].copyWith(read: true);
        changed = true;
      }
    }
    if (changed) {
      _save();
      _notify();
    }
  }

  void remove(String id) {
    final before = _list.length;
    _list.removeWhere((n) => n.id == id);
    if (_list.length < before) {
      _save();
      _notify();
    }
  }

  void clear() {
    _list.clear();
    _save();
    _notify();
  }

  void _notify() {
    try {
      if (!_controller.isClosed) _controller.add(list);
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_list.map((n) => n.toJson()).toList());
      await prefs.setString(_scopedStorageKey, encoded);
    } catch (e) {
      debugPrint('[NotificationService] save error: $e');
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_scopedStorageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as List<dynamic>?;
      if (decoded == null) return;
      _list.clear();
      for (final e in decoded) {
        if (e is Map<String, dynamic>) {
          _list.add(AppNotification.fromJson(e));
        }
      }
      _notify();
    } catch (e) {
      debugPrint('[NotificationService] load error: $e');
    }
  }

  void dispose() {
    _controller.close();
  }
}
