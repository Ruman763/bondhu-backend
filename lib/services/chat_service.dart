import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint, ValueListenable, ValueNotifier;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client_flutter/socket_io_client_flutter.dart';

import '../config/app_config.dart';
import 'supabase_service.dart';
import 'e2e_encryption_service.dart';
import 'message_sync_crypto_service.dart';
import 'privacy_settings_service.dart';
import 'encrypted_local_store.dart';
import 'chat_vibration_service.dart';

// Temporary compatibility mode:
// Keep chat readable across multiple devices/accounts until full multi-device E2E key backup/restore is finalized.
const bool _enableTransportE2E = true;

/// Connection state so UI shows "Connecting" only once, then "Online" or "Reconnecting".
enum ConnectionStatus {
  connecting,
  connected,
  reconnecting,
}

/// Chat item for list (matches website createChatObject).
class ChatItem {
  final String id;
  final String name;
  final String? email;
  final String? avatar;
  final String? lastMessage;
  final String? lastTime;
  final int unread;
  final bool isGlobal;
  final bool isGroup;
  /// If true, suppress message notifications for this chat.
  final bool muteMessages;
  /// If true, suppress call notifications (ringtone) for this chat.
  final bool muteCalls;
  final bool pinned;
  /// When set, chat is archived. Null = not archived.
  final int? archivedAtMs;
  /// When set, chat is snoozed until this time (ms). After that it returns to main list.
  final int? snoozeUntilMs;
  /// Folder label (e.g. Work, Family) for organizing the list.
  final String? folder;
  /// Optional theme color value (Color.value) for this chat.
  final int? themeColor;

  ChatItem({
    required this.id,
    required this.name,
    this.email,
    this.avatar,
    this.lastMessage,
    this.lastTime,
    this.unread = 0,
    this.isGlobal = false,
    this.isGroup = false,
    bool? muteMessages,
    bool? muteCalls,
    this.pinned = false,
    this.archivedAtMs,
    this.snoozeUntilMs,
    this.folder,
    this.themeColor,
  })  : muteMessages = muteMessages ?? false,
        muteCalls = muteCalls ?? false;

  /// True if this chat is currently hidden from main list (archived and not yet snooze comeback).
  bool get isArchived => archivedAtMs != null;
  /// True if snoozed and still within snooze period.
  bool get isSnoozed => snoozeUntilMs != null && DateTime.now().millisecondsSinceEpoch < snoozeUntilMs!;
  /// Snooze has ended; chat can show in main list again.
  bool get isSnoozeEnded => snoozeUntilMs != null && DateTime.now().millisecondsSinceEpoch >= snoozeUntilMs!;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'avatar': avatar,
        'lastMessage': lastMessage,
        'lastTime': lastTime,
        'unread': unread,
        'isGlobal': isGlobal,
        'isGroup': isGroup,
        'muted': muteMessages && muteCalls,
        'muteMessages': muteMessages,
        'muteCalls': muteCalls,
        'pinned': pinned,
        'archivedAtMs': archivedAtMs,
        'snoozeUntilMs': snoozeUntilMs,
        'folder': folder,
        'themeColor': themeColor,
      };

  static bool _bool(dynamic v) => v == true;
  static int? _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : null);

  static ChatItem fromJson(Map<String, dynamic> j) {
    final legacyMuted = _bool(j['muted']);
    final hasMuteMessagesKey = j.containsKey('muteMessages');
    final hasMuteCallsKey = j.containsKey('muteCalls');
    final muteMessages = hasMuteMessagesKey ? _bool(j['muteMessages']) : legacyMuted;
    final muteCalls = hasMuteCallsKey ? _bool(j['muteCalls']) : legacyMuted;

    return ChatItem(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? 'Chat',
      email: j['email'] as String?,
      avatar: j['avatar'] as String?,
      lastMessage: j['lastMessage'] as String?,
      lastTime: j['lastTime'] as String?,
      unread: j['unread'] as int? ?? 0,
      isGlobal: _bool(j['isGlobal']),
      isGroup: _bool(j['isGroup']),
      muteMessages: muteMessages,
      muteCalls: muteCalls,
      pinned: _bool(j['pinned']),
      archivedAtMs: _int(j['archivedAtMs']),
      snoozeUntilMs: _int(j['snoozeUntilMs']),
      folder: j['folder'] as String?,
      themeColor: _int(j['themeColor']),
    );
  }

  ChatItem copyWith({
    String? name,
    String? lastMessage,
    String? lastTime,
    int? unread,
    bool? muteMessages,
    bool? muteCalls,
    bool? pinned,
    int? archivedAtMs,
    int? snoozeUntilMs,
    bool clearArchivedAt = false,
    bool clearSnoozeUntil = false,
    String? folder,
    int? themeColor,
  }) {
    final nextMuteMessages = muteMessages ?? this.muteMessages;
    final nextMuteCalls = muteCalls ?? this.muteCalls;
    return ChatItem(
      id: id,
      name: name ?? this.name,
      email: email,
      avatar: avatar,
      lastMessage: lastMessage ?? this.lastMessage,
      lastTime: lastTime ?? this.lastTime,
      unread: unread ?? this.unread,
      isGlobal: isGlobal,
      isGroup: isGroup,
      muteMessages: nextMuteMessages == true,
      muteCalls: nextMuteCalls == true,
      pinned: pinned ?? this.pinned,
      archivedAtMs: clearArchivedAt ? null : (archivedAtMs ?? this.archivedAtMs),
      snoozeUntilMs: clearSnoozeUntil ? null : (snoozeUntilMs ?? this.snoozeUntilMs),
      folder: folder ?? this.folder,
      themeColor: themeColor ?? this.themeColor,
    );
  }
}

/// Local send status for messages so UI can show "Queued", "Failed", etc.
enum LocalMessageStatus {
  queued,
  sending,
  sent,
  failed,
}

/// Single message (matches website message shape + reaction/reply).
class ChatMessage {
  final String id;
  final String text;
  final bool isMe;
  final String time;
  final String type; // text, image, audio, file, call
  final String? senderId;
  final String? senderName;
  final String? date;
  /// For type == 'call': 'audio' or 'video'.
  final String? callType;
  /// Emoji reaction (e.g. 👍 ❤️).
  final String? reaction;
  /// Reply reference: id of the message being replied to.
  final String? replyToId;
  /// Reply reference: preview text of the message being replied to.
  final String? replyToText;
  /// When set, message was edited. Time string (e.g. "10:30") for "Edited at" display.
  final String? editedAt;
  /// Original text before edit (for "See original" transparency).
  final String? originalText;
  /// When set, message was read by the other party. Time string for "Seen at" display.
  final String? readAt;
  /// When true, sender marked "No rush" so receiver knows they don't need to reply quickly.
  final bool noRush;
  /// When set, message disappears after this time (ms since epoch).
  final int? expiresAtMs;
  /// When true, message is view-once (disappear after open).
  final bool viewOnce;
  /// Link preview title (when text contains URL).
  final String? linkPreviewTitle;
  final String? linkPreviewDesc;
  final String? linkPreviewImage;
  /// Poll: question and options JSON (e.g. ["A","B"]).
  final String? pollQuestion;
  final String? pollOptionsJson;
  /// Local-only status for send state (queued/sending/sent/failed). Not sent to server.
  final LocalMessageStatus? localStatus;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isMe,
    required this.time,
    this.type = 'text',
    this.senderId,
    this.senderName,
    this.date,
    this.callType,
    this.reaction,
    this.replyToId,
    this.replyToText,
    this.editedAt,
    this.originalText,
    this.readAt,
    this.noRush = false,
    this.expiresAtMs,
    this.viewOnce = false,
    this.linkPreviewTitle,
    this.linkPreviewDesc,
    this.linkPreviewImage,
    this.pollQuestion,
    this.pollOptionsJson,
    this.localStatus,
  });

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isMe,
    String? time,
    String? type,
    String? senderId,
    String? senderName,
    String? date,
    String? callType,
    String? reaction,
    String? replyToId,
    String? replyToText,
    String? editedAt,
    String? originalText,
    String? readAt,
    bool? noRush,
    int? expiresAtMs,
    bool? viewOnce,
    String? linkPreviewTitle,
    String? linkPreviewDesc,
    String? linkPreviewImage,
    String? pollQuestion,
    String? pollOptionsJson,
    LocalMessageStatus? localStatus,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        text: text ?? this.text,
        isMe: isMe ?? this.isMe,
        time: time ?? this.time,
        type: type ?? this.type,
        senderId: senderId ?? this.senderId,
        senderName: senderName ?? this.senderName,
        date: date ?? this.date,
        callType: callType ?? this.callType,
        reaction: reaction ?? this.reaction,
        replyToId: replyToId ?? this.replyToId,
        replyToText: replyToText ?? this.replyToText,
        editedAt: editedAt ?? this.editedAt,
        originalText: originalText ?? this.originalText,
        readAt: readAt ?? this.readAt,
        noRush: noRush ?? this.noRush,
        expiresAtMs: expiresAtMs ?? this.expiresAtMs,
        viewOnce: viewOnce ?? this.viewOnce,
        linkPreviewTitle: linkPreviewTitle ?? this.linkPreviewTitle,
        linkPreviewDesc: linkPreviewDesc ?? this.linkPreviewDesc,
        linkPreviewImage: linkPreviewImage ?? this.linkPreviewImage,
        pollQuestion: pollQuestion ?? this.pollQuestion,
        pollOptionsJson: pollOptionsJson ?? this.pollOptionsJson,
        localStatus: localStatus ?? this.localStatus,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isMe': isMe,
        'time': time,
        'type': type,
        'senderId': senderId,
        'senderName': senderName,
        'date': date,
        'callType': callType,
        'reaction': reaction,
        'replyToId': replyToId,
        'replyToText': replyToText,
        'editedAt': editedAt,
        'originalText': originalText,
        'readAt': readAt,
        'noRush': noRush,
        'expiresAtMs': expiresAtMs,
        'viewOnce': viewOnce,
        'linkPreviewTitle': linkPreviewTitle,
        'linkPreviewDesc': linkPreviewDesc,
        'linkPreviewImage': linkPreviewImage,
        'pollQuestion': pollQuestion,
        'pollOptionsJson': pollOptionsJson,
        'localStatus': localStatus?.name,
      };

  static bool _bool(dynamic v) => v == true;
  static int? _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : null);

  static ChatMessage fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String? ?? '',
        text: j['text'] as String? ?? '',
        isMe: j['isMe'] as bool? ?? false,
        time: j['time'] as String? ?? '',
        type: j['type'] as String? ?? 'text',
        senderId: j['senderId'] as String?,
        senderName: j['senderName'] as String?,
        date: j['date'] as String?,
        callType: j['callType'] as String?,
        reaction: j['reaction'] as String?,
        replyToId: j['replyToId'] as String?,
        replyToText: j['replyToText'] as String?,
        editedAt: j['editedAt'] as String?,
        originalText: j['originalText'] as String?,
        readAt: j['readAt'] as String?,
        noRush: _bool(j['noRush']),
        expiresAtMs: _int(j['expiresAtMs']),
        viewOnce: _bool(j['viewOnce']),
        linkPreviewTitle: j['linkPreviewTitle'] as String?,
        linkPreviewDesc: j['linkPreviewDesc'] as String?,
        linkPreviewImage: j['linkPreviewImage'] as String?,
        pollQuestion: j['pollQuestion'] as String?,
        pollOptionsJson: j['pollOptionsJson'] as String?,
        localStatus: _parseLocalStatus(j['localStatus']),
      );

  static LocalMessageStatus? _parseLocalStatus(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString();
    for (final v in LocalMessageStatus.values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

/// Persists chats and messages in memory and via shared_preferences.
/// Protocol matches website: bondhu-v2 useSocket.js + useMessages.js + ChatView.vue (same server, events, payloads).
class ChatService {
  ChatService() {
    _active = this;
  }
  static ChatService? _active;
  static ChatService? get active => _active;

  Socket? _socket;
  String? _userEmail;
  String? _userName;
  String? _currentChatId;
  final List<ChatItem> _chats = [];
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, bool> _typingByChatId = {};
  /// Presence: other users' online state (true = online). Updated by user_online / user_offline from server.
  final Map<String, bool> _onlineByUserId = {};
  /// Last seen time for other users. Updated by server last_seen or by private_message timestamp.
  final Map<String, DateTime> _lastSeenByUserId = {};
  final _chatsController = StreamController<List<ChatItem>>.broadcast();
  final _messagesController = StreamController<Map<String, List<ChatMessage>>>.broadcast();
  final _connectionController = StreamController<ConnectionStatus>.broadcast();
  final _typingController = StreamController<Map<String, bool>>.broadcast();
  final ValueNotifier<int> _presenceTick = ValueNotifier<int>(0);
  bool _hasConnectedBefore = false;
  String? _fcmToken;

  Stream<List<ChatItem>> get chatsStream => _chatsController.stream;
  Stream<Map<String, List<ChatMessage>>> get messagesStream => _messagesController.stream;
  Stream<ConnectionStatus> get connectionStatusStream => _connectionController.stream;
  Stream<Map<String, bool>> get typingStream => _typingController.stream;
  /// Notifier that increments when presence (online/last seen) changes. UI can listen and rebuild.
  ValueListenable<int> get presenceNotifier => _presenceTick;

  /// Called after key migration import succeeds on this account.
  /// Pulls encrypted cloud rows again so newly-imported keys can decrypt them.
  Future<void> recoverAfterMigration() async {
    final ids = _chats
        .map((c) => _normId(c.id))
        .where((id) => id.isNotEmpty && id != 'group_global')
        .toSet()
        .toList();
    for (final id in ids) {
      await syncChatFromCloud(id);
    }
    _saveToStorage();
    _notify();
  }

  List<ChatItem> get chats {
    _clearExpiredSnoozes();
    return List.unmodifiable(_chats);
  }

  void _clearExpiredSnoozes() {
    final now = DateTime.now().millisecondsSinceEpoch;
    bool changed = false;
    for (var i = 0; i < _chats.length; i++) {
      final c = _chats[i];
      if (c.snoozeUntilMs != null && now >= c.snoozeUntilMs!) {
        _chats[i] = c.copyWith(clearArchivedAt: true, clearSnoozeUntil: true);
        changed = true;
      }
    }
    if (changed) {
      _saveToStorage();
      try {
        if (!_chatsController.isClosed) _chatsController.add(List.unmodifiable(_chats));
      } catch (_) {}
    }
  }

  /// Archive or unarchive a chat. When unarchiving, snooze is also cleared.
  void setArchived(String chatId, bool archive) {
    final norm = _normId(chatId);
    final i = _chats.indexWhere((c) => _normId(c.id) == norm);
    if (i < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _chats[i] = _chats[i].copyWith(
      archivedAtMs: archive ? now : null,
      clearArchivedAt: !archive,
      clearSnoozeUntil: true,
    );
    _saveToStorage();
    try {
      if (!_chatsController.isClosed) _chatsController.add(List.unmodifiable(_chats));
    } catch (_) {}
  }

  /// Snooze chat so it hides from main list for [duration], then returns automatically. Better than WhatsApp: choose 24h, 7d, or 30d.
  void setSnooze(String chatId, Duration duration) {
    final norm = _normId(chatId);
    final i = _chats.indexWhere((c) => _normId(c.id) == norm);
    if (i < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final until = now + duration.inMilliseconds;
    _chats[i] = _chats[i].copyWith(
      archivedAtMs: now,
      snoozeUntilMs: until,
    );
    _saveToStorage();
    try {
      if (!_chatsController.isClosed) _chatsController.add(List.unmodifiable(_chats));
    } catch (_) {}
  }

  /// Returns messages for [chatId] sorted by date ascending so date separators (Yesterday, Today) show in correct order.
  List<ChatMessage> getMessages(String chatId) {
    final raw = _messages[chatId] ?? _messages[_normId(chatId)] ?? [];
    if (raw.isEmpty) return List.unmodifiable(raw);
    final sorted = List<ChatMessage>.from(raw);
    sorted.sort((a, b) {
      final aDate = a.date;
      final bDate = b.date;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      final at = DateTime.tryParse(aDate);
      final bt = DateTime.tryParse(bDate);
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });
    return List.unmodifiable(sorted);
  }

  bool get isConnected => _socket?.connected ?? false;

  /// Exposed for WebRTC/call signaling (same socket, call_user, incoming_call, call_accepted, etc.).
  Socket? get socket => _socket;
  String? get userEmail => _userEmail;
  String? get userName => _userName;

  /// Whether the other party is typing in this chat (website: typing listener finds chat by data.email = typer's email).
  bool isTyping(String chatId) => _typingByChatId[_normId(chatId)] == true;

  /// Whether [userId] is currently online (from server user_online / user_offline).
  bool isUserOnline(String userId) => _onlineByUserId[_normId(userId)] == true;

  /// Last seen time for [userId], or null if unknown. Updated by server or by last message from that user.
  DateTime? getLastSeen(String userId) => _lastSeenByUserId[_normId(userId)];

  /// Last message timestamp from the peer in this chat (for "last seen" fallback when server doesn't send last_seen).
  DateTime? getPeerLastMessageTime(String chatId) {
    final peerId = _normId(chatId);
    final list = _messages[chatId] ?? _messages[peerId];
    if (list == null) return null;
    for (var i = list.length - 1; i >= 0; i--) {
      final m = list[i];
      if (m.senderId != null && _normId(m.senderId) == peerId && m.date != null) {
        try {
          return DateTime.tryParse(m.date!);
        } catch (_) {}
        return null;
      }
    }
    return null;
  }

  void _notifyPresence() {
    try {
      _presenceTick.value++;
    } catch (_) {}
  }

  /// Set when user opens a conversation so incoming messages for this chat don't bump unread (matches website).
  void setCurrentChatId(String? chatId) {
    _currentChatId = chatId != null ? _normId(chatId) : null;
  }

  /// Called when a new message arrives and user is not on that chat (for in-app notifications).
  void Function(String chatId, String chatName, String messageText, String? avatarUrl)? onIncomingMessageWhenBackground;

  static String _normId(String? s) => (s ?? '').toString().trim().toLowerCase();

  /// Emit status on the next frame to avoid Flutter assertion _dependents.isEmpty.
  void _emitStatus(ConnectionStatus status) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (!_connectionController.isClosed) _connectionController.add(status);
      } catch (_) {}
    });
  }

  static String formatName(String? str) {
    if (str == null || str.isEmpty) return 'User';
    if (str.contains('@')) str = str.split('@').first;
    return str.isNotEmpty ? '${str[0].toUpperCase()}${str.substring(1)}' : 'User';
  }

  static ChatItem createChatObject(String id, String name, {bool isGroup = false}) =>
      ChatItem(
        id: id,
        name: name,
        email: id.contains('@') ? id : null,
        avatar: 'https://api.dicebear.com/7.x/avataaars/svg?seed=${Uri.encodeComponent(id)}',
        lastMessage: 'New conversation',
        lastTime: '',
        unread: 0,
        isGlobal: id == 'group_global',
        isGroup: isGroup,
      );

  /// Initialize socket and join rooms (matches useSocket.js).
  void init(String userEmail, String userName) {
    if (kDebugMode) debugPrint('[Bondhu Chat] init() called for: ${userEmail.isEmpty ? "(guest)" : userEmail}');
    final raw = userEmail.trim().toLowerCase();
    _userEmail = raw.isEmpty ? 'flutter_${DateTime.now().millisecondsSinceEpoch}@bondhu.app' : raw;
    _userName = userName.isNotEmpty ? userName : formatName(_userEmail);
    // Ensure E2E keys exist on this device so encryption/decryption works (fixes "key issue on every device").
    E2EEncryptionService.instance.ensureKeyPair();

    if (_socket != null) {
      if (kDebugMode) debugPrint('[Bondhu Chat] Socket already exists, skipping create');
      if (_socket!.connected) _joinRooms();
      return;
    }

    _emitStatus(ConnectionStatus.connecting);
    final url = kChatServerUrl;
    if (kDebugMode) debugPrint('[Bondhu Chat] Creating socket to: $url');
    // On web: use polling only so connection completes behind Render/proxies (WebSocket upgrade often fails there).
    final transports = kIsWeb ? ['polling'] : ['websocket'];
    _socket = io(
      url,
      OptionBuilder()
          .setTransports(transports)
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(30)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(15000)
          .build(),
    );

    _socket!.onConnect((_) {
      if (kDebugMode) debugPrint('[Bondhu Chat] Connected to $url');
      _hasConnectedBefore = true;
      _joinRooms();
      _emitStatus(ConnectionStatus.connected);
    });
    _socket!.onConnectError((data) {
      if (kDebugMode) debugPrint('[Bondhu Chat] Connect error to $url: $data');
      if (!_hasConnectedBefore) {
        _emitStatus(ConnectionStatus.connecting);
      } else {
        _emitStatus(ConnectionStatus.reconnecting);
      }
    });
    _socket!.onDisconnect((_) {
      if (_hasConnectedBefore) {
        _emitStatus(ConnectionStatus.reconnecting);
      } else {
        _emitStatus(ConnectionStatus.connecting);
      }
    });
    _socket!.on('error_message', (data) {
      if (kDebugMode) debugPrint('[Bondhu Chat] Server error_message: $data');
    });

    _socket!.on('message', (data) => _onGlobalMessage(data));
    _socket!.on('private_message', (data) => _onPrivateMessage(data));
    _socket!.on('typing', (data) => _onTyping(data));
    _socket!.on('message_reaction', (data) => _onMessageReaction(data));
    _socket!.on('edit_message', (data) => _onEditMessage(data));
    _socket!.on('read_receipt', (data) => _onReadReceipt(data));
    // Presence: server should emit user_online / user_offline (payload: { email: string }) so we show real status.
    _socket!.on('user_online', _onUserOnline);
    _socket!.on('user_offline', _onUserOffline);
    _socket!.on('users_online', _onUsersOnline);

    // Connect once after handlers are registered (disableAutoConnect avoids double-connect).
    // Schedule connect so we don't block the current frame (avoids UI freeze on web).
    if (kDebugMode) debugPrint('[Bondhu Chat] Calling connect()...');
    Future.microtask(() {
      _socket?.connect();
    });

    // If still not connected after 20s (e.g. server cold start or proxy), retry once.
    Future.delayed(const Duration(seconds: 20), () {
      if (_socket != null && !_socket!.connected && !_hasConnectedBefore) {
        if (kDebugMode) debugPrint('[Bondhu Chat] Still not connected after 20s, retrying...');
        _socket!.disconnect();
        _socket!.connect();
      }
    });

    _loadFromStorage().then((_) {
      if (!_chats.any((c) => c.id == 'group_global')) {
        _chats.insert(0, createChatObject('group_global', 'Global Chat'));
        _saveToStorage();
      }
      // Professional restore path: merge server-side contacts/chats with local cache after login.
      _rehydrateFromServer();
      // Defer first emit to next frame so listeners are attached without assertion issues.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (!_chatsController.isClosed) _chatsController.add(chats);
        } catch (_) {}
      });
    });
  }

  Future<void> _rehydrateFromServer() async {
    final me = _userEmail?.trim().toLowerCase();
    if (me == null || me.isEmpty) return;
    try {
      final ids = <String>{};
      final fromProfile = await getContactUserIds(me);
      ids.addAll(fromProfile.map((e) => _normId(e)).where((e) => e.isNotEmpty && e != me));
      for (final c in _chats) {
        if (!c.isGlobal && !c.isGroup) {
          final id = _normId(c.id);
          if (id.isNotEmpty && id != me) ids.add(id);
        }
      }
      if (ids.isEmpty) return;

      final profiles = await getProfilesByIds(ids.toList());
      var changed = false;
      for (final p in profiles) {
        final id = _normId(p.userId);
        if (id.isEmpty || id == me) continue;
        final i = _chats.indexWhere((c) => _normId(c.id) == id);
        if (i < 0) {
          _chats.add(ChatItem(
            id: id,
            name: p.name.isNotEmpty ? p.name : formatName(id),
            email: p.userId,
            avatar: p.avatar,
            lastMessage: '',
            lastTime: '',
          ));
          changed = true;
        } else {
          final existing = _chats[i];
          final betterName = p.name.trim().isNotEmpty ? p.name.trim() : existing.name;
          final betterAvatar = p.avatar.trim().isNotEmpty ? p.avatar.trim() : (existing.avatar ?? '');
          if (existing.name != betterName || (existing.avatar ?? '') != betterAvatar) {
            _chats[i] = ChatItem(
              id: existing.id,
              name: betterName,
              email: existing.email ?? p.userId,
              avatar: betterAvatar,
              lastMessage: existing.lastMessage,
              lastTime: existing.lastTime,
              unread: existing.unread,
              isGlobal: existing.isGlobal,
              isGroup: existing.isGroup,
              muteMessages: existing.muteMessages,
              muteCalls: existing.muteCalls,
              pinned: existing.pinned,
              archivedAtMs: existing.archivedAtMs,
              snoozeUntilMs: existing.snoozeUntilMs,
              folder: existing.folder,
              themeColor: existing.themeColor,
            );
            changed = true;
          }
        }
      }

      // Hydrate messages from cloud backup/history for known private chats.
      for (final id in ids.take(100)) {
        try {
          await syncChatFromCloud(id);
        } catch (_) {}
      }

      if (changed) {
        _saveToStorage();
        _notify();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Bondhu Chat] server rehydrate failed: $e');
    }
  }

  void _joinRooms() {
    if (_socket == null || _userEmail == null || _userEmail!.isEmpty) return;
    _socket!.emit('join_room', _userEmail);
    _socket!.emit('join_room', 'group_global');
    // Only broadcast "online" if user has "Show online status" on; include showLastSeen for server to hide our last seen when off.
    if (PrivacySettingsService.instance.showOnlineStatusOn.value) {
      _socket!.emit('user_online', {
        'email': _userEmail,
        'name': _userName,
        'showLastSeen': PrivacySettingsService.instance.lastSeenOn.value,
      });
    }
    _emitFcmTokenIfReady();
    fetchAndProcessQueuedMessages();
  }

  /// Register device FCM token with server for push notifications. Call when token is available.
  void registerFcmToken(String? token) {
    _fcmToken = token;
    _emitFcmTokenIfReady();
  }

  void _emitFcmTokenIfReady() {
    if (_socket == null || !_socket!.connected || _fcmToken == null || _userEmail == null) return;
    _socket!.emit('register_fcm', {'email': _userEmail!.trim().toLowerCase(), 'token': _fcmToken});
  }

  /// Fetch queued messages from Supabase (store-and-forward when user was offline) and process like incoming private messages.
  Future<void> fetchAndProcessQueuedMessages() async {
    final email = _userEmail?.trim().toLowerCase();
    if (email == null || email.isEmpty) return;
    try {
      final docs = await getQueuedMessages(email);
      if (docs.isEmpty) return;
      if (kDebugMode) debugPrint('[Bondhu Chat] Processing ${docs.length} queued message(s)');
      final toDelete = <String>[];
      for (final doc in docs) {
        final data = doc.data;
        final senderId = (data['senderId'] as String?)?.trim().toLowerCase() ?? '';
        final chatId = _normId(senderId);
        if (chatId.isEmpty) {
          toDelete.add(doc.$id);
          continue;
        }
        final msgId = _messageIdToString(data['msgId']);
        final existing = _messages[chatId] ?? _messages[_normId(chatId)];
        if (existing != null && existing.any((m) => m.id == msgId)) {
          toDelete.add(doc.$id);
          continue;
        }
        ChatItem? chat;
        for (final c in _chats) {
          if (_normId(c.id) == chatId) {
            chat = c;
            break;
          }
        }
        if (chat == null) {
          chat = createChatObject(chatId, (data['senderName'] as String?)?.trim().isNotEmpty == true
              ? (data['senderName'] as String).trim()
              : formatName(senderId));
          _chats.insert(0, chat);
        }
        final rawText = (data['payload'] as String?) ?? '';
        final map = <String, dynamic>{
          'id': msgId,
          'senderId': senderId,
          'text': rawText,
          'type': data['type'] ?? 'text',
          'timestamp': data['timestamp']?.toString() ?? DateTime.now().toIso8601String(),
          'author': data['senderName']?.toString(),
        };
        await _decryptPrivateMessageThenAppend(chatId, chat, map, rawText);
        toDelete.add(doc.$id);
      }
      if (toDelete.isNotEmpty) await deleteQueuedMessages(toDelete);
    } catch (e) {
      if (kDebugMode) debugPrint('[Bondhu Chat] fetchAndProcessQueuedMessages error: $e');
    }
  }

  void _onGlobalMessage(dynamic data) {
    final map = _parseMessageData(data);
    if (map == null) return;
    if (_normId(map['senderId'] as String?) == _normId(_userEmail)) return;

    if (kDebugMode) debugPrint('[Bondhu Chat] Received global message: ${map['text']} from ${map['senderId']}');

    const chatId = 'group_global';
    if (!_chats.any((c) => c.id == chatId)) {
      _chats.insert(0, createChatObject(chatId, 'Global Chat'));
    }
    final msg = ChatMessage(
      id: _messageIdToString(map['id']),
      text: map['text']?.toString() ?? '',
      isMe: false,
      time: _formatTime(map['timestamp']),
      type: map['type']?.toString() ?? 'text',
      senderId: map['senderId']?.toString(),
      senderName: (map['author'] ?? formatName(map['senderId']))?.toString(),
      date: map['timestamp']?.toString(),
      replyToId: map['replyToId']?.toString(),
      replyToText: map['replyToText']?.toString(),
    );
    _messages.putIfAbsent(chatId, () => []).add(msg);
    _trimMessages(chatId);
    final incrementUnread = _currentChatId != chatId;
    _updateChatPreview(chatId, msg.text, msg.time, incrementUnread: incrementUnread);
    final suppressed = _isChatMutedForMessages(chatId);
    if (!suppressed) {
      ChatVibrationService.instance.triggerForNewMessage(chatId: chatId);
    }
    if (incrementUnread && !suppressed) {
      onIncomingMessageWhenBackground?.call(chatId, 'Global Chat', msg.text, null);
    }
    _saveToStorage();
    _notify();
  }

  void _onUserOnline(dynamic data) {
    final email = _parsePresenceEmail(data);
    if (email.isEmpty) return;
    if (_onlineByUserId[email] == true) return;
    _onlineByUserId[email] = true;
    if (kDebugMode) debugPrint('[Bondhu Chat] user_online: $email');
    _notifyPresence();
  }

  void _onUserOffline(dynamic data) {
    final email = _parsePresenceEmail(data);
    if (email.isEmpty) return;
    _onlineByUserId[email] = false;
    _lastSeenByUserId[email] = DateTime.now();
    if (kDebugMode) debugPrint('[Bondhu Chat] user_offline: $email');
    _notifyPresence();
  }

  void _onUsersOnline(dynamic data) {
    final list = _parseUsersOnlineList(data);
    if (list == null) return;
    final set = list.map((e) => _normId(e)).toSet();
    for (final e in _onlineByUserId.keys.toList()) {
      if (!set.contains(e)) _onlineByUserId[e] = false;
    }
    for (final e in set) {
      _onlineByUserId[e] = true;
    }
    if (kDebugMode) debugPrint('[Bondhu Chat] users_online: ${list.length}');
    _notifyPresence();
  }

  static String _parsePresenceEmail(dynamic data) {
    if (data is Map) {
      final email = data['email']?.toString().trim().toLowerCase();
      if (email != null && email.isNotEmpty) return email;
    }
    if (data is String) return (data).trim().toLowerCase();
    return '';
  }

  static List<String>? _parseUsersOnlineList(dynamic data) {
    if (data is List) {
      return data.map((e) => ((e is String) ? e : (e?.toString() ?? '')).trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
    }
    return null;
  }

  void _onPrivateMessage(dynamic data) {
    final map = _parseMessageData(data);
    if (map == null) return;
    if (_normId(map['senderId'] as String?) == _normId(_userEmail)) return;

    final chatId = _normId(map['senderId'] as String?);
    if (chatId.isEmpty) return;
    // Update last seen from message timestamp (fallback when server doesn't send last_seen)
    final ts = map['timestamp']?.toString();
    if (ts != null && ts.isNotEmpty) {
      final dt = DateTime.tryParse(ts);
      if (dt != null) {
        final prev = _lastSeenByUserId[chatId];
        if (prev == null || dt.isAfter(prev)) {
          _lastSeenByUserId[chatId] = dt;
          _notifyPresence();
        }
      }
    }

    ChatItem? chat;
    for (final c in _chats) {
      if (_normId(c.id) == chatId) {
        chat = c;
        break;
      }
    }
    if (chat == null) {
      chat = createChatObject(chatId, formatName(map['senderId'] as String? ?? chatId));
      _chats.insert(0, chat);
    }

    // Auto-add sender to contacts when someone sends you a message
    final myEmail = _userEmail?.trim().toLowerCase();
    if (myEmail != null && chatId.isNotEmpty && chatId.contains('@')) {
      addContactToProfile(myEmail, chatId);
    }

    final rawText = map['text']?.toString() ?? '';
    _decryptPrivateMessageThenAppend(chatId, chat, map, rawText);
  }

  /// Decrypts [rawText] if it's an E2E payload, then appends the message and notifies.
  Future<void> _decryptPrivateMessageThenAppend(String chatId, ChatItem chat, Map<String, dynamic> map, String rawText) async {
    String displayText = rawText;
    final isDbPayload = MessageSyncCryptoService.isDbSyncPayload(rawText);
    final isE2EPayload = _looksLikeE2EPayload(rawText);
    if (isDbPayload) {
      try {
        final decrypted = await MessageSyncCryptoService.instance.decryptStoredPayload(rawText);
        if (decrypted != null && decrypted.isNotEmpty) {
          displayText = decrypted;
        } else {
          // New device without key migration yet: keep chat clean (no placeholder bubbles).
          return;
        }
      } catch (_) {
        return;
      }
    } else if (isE2EPayload) {
      try {
        displayText = await E2EEncryptionService.instance.decrypt(rawText);
        if (kDebugMode) debugPrint('[Bondhu Chat] Decrypted private message from ${map['senderId']}');
      } catch (_) {
        return;
      }
    } else if (kDebugMode) {
      debugPrint('[Bondhu Chat] Received private message: $rawText from ${map['senderId']}');
    }

    final msg = ChatMessage(
      id: _messageIdToString(map['id']),
      text: displayText,
      isMe: false,
      time: _formatTime(map['timestamp']),
      type: map['type']?.toString() ?? 'text',
      senderId: map['senderId']?.toString(),
      senderName: (map['author'] ?? formatName(map['senderId']))?.toString(),
      date: map['timestamp']?.toString(),
      replyToId: map['replyToId']?.toString(),
      replyToText: map['replyToText']?.toString(),
      noRush: map['noRush'] == true,
    );
    _messages.putIfAbsent(chatId, () => []).add(msg);
    _trimMessages(chatId);
    final incrementUnread = _currentChatId != chatId;
    _updateChatPreview(chatId, msg.text, msg.time, incrementUnread: incrementUnread);
    final suppressed = _isChatMutedForMessages(chatId);
    if (!suppressed) {
      ChatVibrationService.instance.triggerForNewMessage(chatId: chatId);
    }
    if (incrementUnread && !suppressed) {
      onIncomingMessageWhenBackground?.call(chatId, chat.name, msg.text, chat.avatar);
    }
    _saveToStorage();
    _notify();
  }

  static bool _looksLikeE2EPayload(String s) {
    if (s.isEmpty || s.length < 50) return false;
    Map<String, dynamic>? payload;
    // 1) Try standard base64
    try {
      final decoded = utf8.decode(base64.decode(s));
      final j = jsonDecode(decoded);
      if (j is Map<String, dynamic>) payload = j;
    } catch (_) {
      // 2) Try base64url (web clients may use this)
      try {
        final normalized = s.replaceAll('-', '+').replaceAll('_', '/');
        final padding = (4 - normalized.length % 4) % 4;
        final decoded = utf8.decode(base64.decode(normalized + ('=' * padding)));
        final j = jsonDecode(decoded);
        if (j is Map<String, dynamic>) payload = j;
      } catch (_) {
        // 3) Finally, treat as raw JSON payload (no outer base64)
        try {
          final j = jsonDecode(s);
          if (j is Map<String, dynamic>) payload = j;
        } catch (_) {
          return false;
        }
      }
    }
    if (payload == null) return false;
    return payload.containsKey('v') &&
        payload.containsKey('iv') &&
        payload.containsKey('content') &&
        payload.containsKey('key');
  }

  Map<String, dynamic>? _parseMessageData(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        return jsonDecode(data) as Map<String, dynamic>?;
      } catch (_) {}
    }
    return null;
  }

  /// Server may send id as number (Date.now()) or string; normalize to string (matches website).
  static String _messageIdToString(dynamic id) {
    if (id == null) return DateTime.now().millisecondsSinceEpoch.toString();
    if (id is int) return id.toString();
    return id.toString();
  }

  String _formatTime(dynamic t) {
    if (t == null) return _timeNow();
    if (t is String) {
      final d = DateTime.tryParse(t);
      if (d != null) return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return _timeNow();
  }

  String _timeNow() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  void _trimMessages(String chatId, [int max = 500]) {
    final list = _messages[chatId];
    if (list == null || list.length <= max) return;
    _messages[chatId] = list.sublist(list.length - max);
  }

  void _updateChatPreview(String chatId, String lastMessage, String lastTime,
      {bool incrementUnread = false}) {
    final norm = _normId(chatId);
    final i = _chats.indexWhere((c) => _normId(c.id) == norm);
    if (i < 0) return;
    final c = _chats[i];
    final updated = c.copyWith(
      lastMessage: lastMessage,
      lastTime: lastTime,
      unread: incrementUnread ? c.unread + 1 : c.unread,
    );
    _chats.removeAt(i);
    // Keep pinned chats at the top section; move latest chat to the front of its section.
    if (updated.pinned == true) {
      _chats.insert(0, updated);
    } else {
      var insertAt = 0;
      while (insertAt < _chats.length && _chats[insertAt].pinned == true) {
        insertAt++;
      }
      _chats.insert(insertAt, updated);
    }
  }

  void _notify() {
    try {
      if (!_chatsController.isClosed) _chatsController.add(chats);
      if (!_messagesController.isClosed) _messagesController.add(Map.from(_messages));
    } catch (_) {}
  }

  /// Send message (matches useMessages.sendMessage).
  /// Always adds to local UI (optimistic). For private text messages, encrypts with recipient's E2E public key when available.
  Future<void> sendMessage(String chatId, String content, String type,
      {String? author, String? replyToId, String? replyToText, bool noRush = false}) async {
    final timestamp = DateTime.now().toIso8601String();
    final msgId = DateTime.now().millisecondsSinceEpoch;
    final timeStr = _timeNow();
    final initialStatus = (_socket == null || !_socket!.connected)
        ? LocalMessageStatus.queued
        : LocalMessageStatus.sending;
    final msg = ChatMessage(
      id: msgId.toString(),
      text: content,
      isMe: true,
      time: timeStr,
      type: type,
      senderId: _userEmail,
      senderName: _userName,
      date: timestamp,
      replyToId: replyToId,
      replyToText: replyToText,
      noRush: noRush,
      localStatus: initialStatus,
    );
    _messages.putIfAbsent(chatId, () => []).add(msg);
    _trimMessages(chatId);
    _updateChatPreview(chatId, type == 'text' ? content : 'Sent $type', timeStr);
    _saveToStorage();
    _notify();

    if (_socket == null || !_socket!.connected) {
      // Keep as queued; user can retry when back online.
      return;
    }

    String payloadText = content;
    final isPrivate = chatId != 'group_global';
    if (_enableTransportE2E && isPrivate && type == 'text' && content.isNotEmpty) {
      try {
        final profile = await getProfileByUserId(_normId(chatId));
        if (profile?.publicKey != null && profile!.publicKey!.isNotEmpty) {
          final encrypted = await E2EEncryptionService.instance.encrypt(content, profile.publicKey!);
          if (encrypted != null) payloadText = encrypted;
        }
      } catch (_) {}
    }

    final messageData = <String, dynamic>{
      'id': msgId,
      'senderId': _userEmail,
      'text': payloadText,
      'type': type,
      'timestamp': timestamp,
    };
    if (replyToId != null) messageData['replyToId'] = replyToId;
    if (replyToText != null) messageData['replyToText'] = replyToText;
    if (noRush) messageData['noRush'] = true;
    // Optional: Save encrypted backup copy to Supabase messages table when cloud backup is enabled.
    await _maybeBackupMessageToCloud(
      chatId: chatId,
      content: content,
      timestamp: timestamp,
    );

    if (isPrivate) {
      messageData['targetId'] = chatId;
      try {
        _socket!.emit('private_message', messageData);
        _updateLocalStatus(chatId, msg.id, LocalMessageStatus.sent);
      } catch (_) {
        _updateLocalStatus(chatId, msg.id, LocalMessageStatus.failed);
      }
      sendToQueue(
        recipient: chatId,
        senderId: _userEmail!,
        senderName: _userName ?? '',
        payload: payloadText,
        msgId: msgId.toString(),
        type: type,
      );
      final myEmail = _userEmail?.trim().toLowerCase();
      final otherId = _normId(chatId);
      if (myEmail != null && otherId.isNotEmpty && otherId.contains('@')) {
        addContactToProfile(myEmail, otherId);
      }
    } else {
      messageData['author'] = author ?? _userName;
      messageData['authorEmail'] = _userEmail;
      try {
        _socket!.emit('message', messageData);
        _updateLocalStatus(chatId, msg.id, LocalMessageStatus.sent);
      } catch (_) {
        _updateLocalStatus(chatId, msg.id, LocalMessageStatus.failed);
      }
    }
  }

  void _updateLocalStatus(String chatId, String messageId, LocalMessageStatus status) {
    final norm = _normId(chatId);
    final list = _messages[norm];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final updated = List<ChatMessage>.from(list)
      ..[idx] = list[idx].copyWith(localStatus: status);
    _messages[norm] = updated;
    _saveToStorage();
    _notify();
  }

  Future<void> _maybeBackupMessageToCloud({
    required String chatId,
    required String content,
    required String timestamp,
  }) async {
    try {
      final enabled = await cloudMessageBackupEnabledFor(_userEmail);
      if (!enabled) return;
      final myId = _userEmail?.trim().toLowerCase();
      if (myId == null || myId.isEmpty) return;

      final encrypted = await MessageSyncCryptoService.instance.encryptPlaintext(content);
      if (encrypted == null || encrypted.isEmpty) return;

      await saveMessageToTable(
        myId,
        _normId(chatId),
        encrypted,
        timestamp: timestamp,
      );
    } catch (_) {}
  }

  /// Retry sending a previously queued/failed outgoing message.
  Future<void> retrySendMessage(String chatId, String messageId) async {
    if (_socket == null || !_socket!.connected) return;
    final norm = _normId(chatId);
    final list = _messages[norm];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId && m.isMe);
    if (idx < 0) return;
    final msg = list[idx];
    final isPrivate = chatId != 'group_global';
    _updateLocalStatus(chatId, messageId, LocalMessageStatus.sending);

    String payloadText = msg.text;
    if (_enableTransportE2E && isPrivate && msg.type == 'text' && msg.text.isNotEmpty) {
      try {
        final profile = await getProfileByUserId(_normId(chatId));
        if (profile?.publicKey != null && profile!.publicKey!.isNotEmpty) {
          final encrypted = await E2EEncryptionService.instance.encrypt(msg.text, profile.publicKey!);
          if (encrypted != null) payloadText = encrypted;
        }
      } catch (_) {}
    }

    final messageData = <String, dynamic>{
      'id': int.tryParse(msg.id) ?? DateTime.now().millisecondsSinceEpoch,
      'senderId': _userEmail,
      'text': payloadText,
      'type': msg.type,
      'timestamp': msg.date ?? DateTime.now().toIso8601String(),
    };

    if (msg.replyToId != null) messageData['replyToId'] = msg.replyToId;
    if (msg.replyToText != null) messageData['replyToText'] = msg.replyToText;
    if (msg.noRush) messageData['noRush'] = true;

    if (isPrivate) {
      messageData['targetId'] = chatId;
      try {
        _socket!.emit('private_message', messageData);
        _updateLocalStatus(chatId, messageId, LocalMessageStatus.sent);
      } catch (_) {
        _updateLocalStatus(chatId, messageId, LocalMessageStatus.failed);
      }
    } else {
      messageData['author'] = _userName;
      messageData['authorEmail'] = _userEmail;
      try {
        _socket!.emit('message', messageData);
        _updateLocalStatus(chatId, messageId, LocalMessageStatus.sent);
      } catch (_) {
        _updateLocalStatus(chatId, messageId, LocalMessageStatus.failed);
      }
    }
  }

  /// Sync messages for a private chat from encrypted cloud backup.
  Future<void> syncChatFromCloud(String chatId) async {
    final myId = _userEmail?.trim().toLowerCase();
    if (myId == null || myId.isEmpty) return;
    final normChat = _normId(chatId);
    if (normChat == 'group_global') return;
    try {
      final docs = await getChatHistory(myId, normChat);
      if (docs.isEmpty) return;
      final existing = _messages[normChat] ?? [];
      final existingIds = existing.map((m) => m.id).toSet();
      final List<ChatMessage> added = [];
      for (final doc in docs) {
        final data = doc.data;
        final ts = data['timestamp']?.toString() ?? DateTime.now().toIso8601String();
        final id = ts;
        if (existingIds.contains(id)) continue;
        final cipher = (data['text'] as String?) ?? '';
        if (cipher.isEmpty) continue;
        String plain = cipher;
        if (MessageSyncCryptoService.isDbSyncPayload(cipher)) {
          final d = await MessageSyncCryptoService.instance.decryptStoredPayload(cipher);
          if (d != null && d.isNotEmpty) {
            plain = d;
          } else {
            // No key on this device yet -> skip message until migration completes.
            continue;
          }
        } else if (_looksLikeE2EPayload(cipher)) {
          try {
            plain = await E2EEncryptionService.instance.decrypt(cipher);
          } catch (_) {
            continue;
          }
        }
        final msg = ChatMessage(
          id: id,
          text: plain,
          isMe: true,
          time: _formatTime(ts),
          type: 'text',
          senderId: myId,
          senderName: _userName,
          date: ts,
        );
        added.add(msg);
      }
      if (added.isEmpty) return;
      final list = List<ChatMessage>.from(existing)..addAll(added);
      _messages[normChat] = list;
      _trimMessages(normChat);
      _saveToStorage();
      _notify();
    } catch (_) {}
  }

  /// Delete a message from local list (for me only). Persists and notifies.
  void deleteMessage(String chatId, String msgId) {
    final norm = _normId(chatId);
    final list = _messages[norm];
    if (list == null) return;
    final newList = list.where((m) => m.id != msgId).toList();
    if (newList.length == list.length) return;
    _messages[norm] = newList;
    _saveToStorage();
    _notify();
  }

  /// Edit a message. Better than WhatsApp: keeps original for "See original" transparency.
  void editMessage(String chatId, String msgId, String newText) {
    final norm = _normId(chatId);
    final list = _messages[norm];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == msgId);
    if (idx < 0) return;
    final msg = list[idx];
    if (msg.type != 'text') return;
    final timeStr = _timeNow();
    final updated = msg.copyWith(
      text: newText,
      editedAt: timeStr,
      originalText: msg.originalText ?? msg.text,
    );
    _messages[norm] = List<ChatMessage>.from(list)..[idx] = updated;
    _saveToStorage();
    _notify();
    if (_socket != null && _socket!.connected) {
      _socket!.emit('edit_message', {
        'target': chatId,
        'msgId': msgId,
        'text': newText,
        'senderId': _userEmail,
      });
    }
  }

  /// Set reaction on a message and emit to server (matches website message_reaction).
  void setMessageReaction(String chatId, String msgId, String emoji) {
    final norm = _normId(chatId);
    final list = _messages[norm];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == msgId);
    if (idx < 0) return;
    final updated = List<ChatMessage>.from(list)
      ..[idx] = list[idx].copyWith(reaction: emoji);
    _messages[norm] = updated;
    _saveToStorage();
    _notify();
    if (_socket != null && _socket!.connected) {
      _socket!.emit('message_reaction', {
        'target': chatId,
        'msgId': msgId,
        'emoji': emoji,
        'senderId': _userEmail,
      });
    }
  }

  void emitTyping(String targetChatId, bool status) {
    if (_socket == null || !_socket!.connected) return;
    _socket!.emit('typing', {
      'target': targetChatId,
      'email': _userEmail,
      'status': status,
    });
  }

  /// Add a call history entry to the chat (matches bondhu-v2 call_history / addCallHistoryMessage).
  void addCallHistoryMessage(String chatId, String callType, String durationFormatted, bool isMe) {
    final norm = _normId(chatId);
    if (!_chats.any((c) => _normId(c.id) == norm)) return;
    final label = callType == 'video' ? 'Video call' : 'Voice call';
    final text = durationFormatted.isNotEmpty ? '$label • $durationFormatted' : label;
    final msg = ChatMessage(
      id: 'call-${DateTime.now().millisecondsSinceEpoch}',
      text: text,
      isMe: isMe,
      time: _timeNow(),
      type: 'call',
      callType: callType,
      senderId: isMe ? _userEmail : null,
      senderName: isMe ? _userName : null,
    );
    _messages.putIfAbsent(chatId, () => []).add(msg);
    _trimMessages(chatId);
    _updateChatPreview(chatId, text, msg.time);
    _saveToStorage();
    _notify();
  }

  void _onTyping(dynamic data) {
    final map = _parseMessageData(data);
    if (map == null) return;
    final email = map['email']?.toString().trim().toLowerCase();
    if (email == null || email.isEmpty) return;
    final status = map['status'] == true;
    if (_typingByChatId[email] == status) return;
    _typingByChatId[email] = status;
    _notifyTyping();
  }

  void _onMessageReaction(dynamic data) {
    final map = data is Map ? Map<String, dynamic>.from(data) : null;
    if (map == null) return;
    final msgId = _messageIdToString(map['msgId']);
    final emoji = map['emoji']?.toString();
    if (emoji == null || emoji.isEmpty) return;
    final senderId = _normId(map['senderId']?.toString());
    final targetId = _normId(map['target']?.toString());
    final chatId = targetId.isNotEmpty ? targetId : (senderId == _normId(_userEmail) ? null : senderId);
    if (chatId == null) return;
    final list = _messages[chatId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == msgId);
    if (idx < 0) return;
    _messages[chatId] = List.from(list)..[idx] = list[idx].copyWith(reaction: emoji);
    _saveToStorage();
    _notify();
  }

  void _onEditMessage(dynamic data) {
    final map = data is Map ? Map<String, dynamic>.from(data) : null;
    if (map == null) return;
    final msgId = _messageIdToString(map['msgId']);
    final newText = map['text']?.toString();
    if (newText == null) return;
    final chatId = _normId(map['target']?.toString());
    if (chatId.isEmpty) return;
    final list = _messages[chatId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == msgId);
    if (idx < 0) return;
    final msg = list[idx];
    final timeStr = _timeNow();
    _messages[chatId] = List.from(list)
      ..[idx] = msg.copyWith(
        text: newText,
        editedAt: timeStr,
        originalText: msg.originalText ?? msg.text,
      );
    _saveToStorage();
    _notify();
  }

  void _onReadReceipt(dynamic data) {
    final map = data is Map ? Map<String, dynamic>.from(data) : null;
    if (map == null) return;
    final msgId = _messageIdToString(map['msgId']);
    final readAt = map['readAt']?.toString();
    if (readAt == null) return;
    final chatId = _normId(map['target']?.toString());
    if (chatId.isEmpty) return;
    final list = _messages[chatId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == msgId);
    if (idx < 0) return;
    _messages[chatId] = List.from(list)
      ..[idx] = list[idx].copyWith(readAt: readAt);
    _saveToStorage();
    _notify();
  }

  /// Call when user opens a chat to mark messages as read. Only emits if "Share read receipts" is on. Backend should broadcast read_receipt to sender.
  Future<void> markRead(String chatId, List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    await PrivacySettingsService.instance.load();
    if (!PrivacySettingsService.instance.readReceiptsOn.value) return;
    if (_socket == null || !_socket!.connected) return;
    _socket!.emit('mark_read', {
      'target': chatId,
      'messageIds': messageIds,
      'readerId': _userEmail,
    });
  }

  void _notifyTyping() {
    try {
      if (!_typingController.isClosed) _typingController.add(Map.from(_typingByChatId));
    } catch (_) {}
  }

  void addChat(ChatItem chat) {
    if (_chats.any((c) => _normId(c.id) == _normId(chat.id))) return;
    _chats.insert(0, chat);
    _messages[chat.id] = [];
    if (chat.isGroup && _socket != null && _socket!.connected) {
      _socket!.emit('join_room', chat.id);
    }
    _saveToStorage();
    try {
      if (!_chatsController.isClosed) _chatsController.add(chats);
    } catch (_) {}
  }

  void selectChat(String? chatId) {
    if (chatId == null) return;
    final norm = _normId(chatId);
    final i = _chats.indexWhere((c) => _normId(c.id) == norm);
    if (i < 0) return;
    final c = _chats[i];
    if (c.unread > 0) {
      _chats[i] = c.copyWith(unread: 0);
      _saveToStorage();
      try {
        if (!_chatsController.isClosed) _chatsController.add(chats);
      } catch (_) {}
    }
  }

  /// Remove a chat and all its messages from memory and persistence.
  void removeChat(String chatId) {
    final norm = _normId(chatId);
    final i = _chats.indexWhere((c) => _normId(c.id) == norm);
    if (i < 0) return;
    final removedId = _chats[i].id;
    _chats.removeAt(i);
    _messages.remove(removedId);
    _messages.remove(chatId);
    _messages.remove(norm);
    _saveToStorage();
    try {
      if (!_chatsController.isClosed) _chatsController.add(chats);
      if (!_messagesController.isClosed) _messagesController.add(Map.from(_messages));
    } catch (_) {}
  }

  /// Clear all messages in a chat; chat stays in list.
  void clearMessages(String chatId) {
    final norm = _normId(chatId);
    final i = _chats.indexWhere((c) => _normId(c.id) == norm);
    if (i < 0) return;
    for (final key in _messages.keys.toList()) {
      if (_normId(key) == norm) _messages.remove(key);
    }
    _chats[i] = _chats[i].copyWith(lastMessage: null, lastTime: null);
    _saveToStorage();
    try {
      if (!_chatsController.isClosed) _chatsController.add(chats);
      if (!_messagesController.isClosed) _messagesController.add(Map.from(_messages));
    } catch (_) {}
  }

  /// Mark chat as having one unread (e.g. from info screen "Mark unread").
  void markUnread(String chatId) {
    final norm = _normId(chatId);
    final i = _chats.indexWhere((c) => _normId(c.id) == norm);
    if (i < 0) return;
    final c = _chats[i];
    _chats[i] = c.copyWith(unread: c.unread + 1);
    _saveToStorage();
    try {
      if (!_chatsController.isClosed) _chatsController.add(chats);
    } catch (_) {}
  }

  /// Update per-chat mute settings. Any parameter left null keeps its current value.
  void setMuteSettings(String chatId, {bool? muteMessages, bool? muteCalls}) {
    final norm = _normId(chatId);
    final i = _chats.indexWhere((c) => _normId(c.id) == norm);
    if (i < 0) return;
    _chats[i] = _chats[i].copyWith(
      muteMessages: muteMessages,
      muteCalls: muteCalls,
    );
    _saveToStorage();
    try {
      if (!_chatsController.isClosed) _chatsController.add(chats);
    } catch (_) {}
  }

  /// Legacy helper: mute/unmute both messages and calls together.
  void setMuted(String chatId, bool muted) {
    setMuteSettings(chatId, muteMessages: muted, muteCalls: muted);
  }

  bool _isChatMutedForMessages(String chatId) {
    final norm = _normId(chatId);
    for (final c in _chats) {
      if (_normId(c.id) == norm) return c.muteMessages;
    }
    return false;
  }

  bool isChatMutedForMessages(String chatId) => _isChatMutedForMessages(chatId);

  bool isChatMutedForCalls(String chatId) {
    final norm = _normId(chatId);
    for (final c in _chats) {
      if (_normId(c.id) == norm) return c.muteCalls;
    }
    return false;
  }

  void setPinned(String chatId, bool pinned) {
    final norm = _normId(chatId);
    final i = _chats.indexWhere((c) => _normId(c.id) == norm);
    if (i < 0) return;
    _chats[i] = _chats[i].copyWith(pinned: pinned);
    _saveToStorage();
    try {
      if (!_chatsController.isClosed) _chatsController.add(chats);
    } catch (_) {}
  }

  /// Set which profile audience this chat sees (e.g. Personal, Work). Null = Default.
  void setFolder(String chatId, String? folderName) {
    final norm = _normId(chatId);
    final i = _chats.indexWhere((c) => _normId(c.id) == norm);
    if (i < 0) return;
    _chats[i] = _chats[i].copyWith(folder: folderName?.trim().isEmpty == true ? null : folderName?.trim());
    _saveToStorage();
    try {
      if (!_chatsController.isClosed) _chatsController.add(chats);
    } catch (_) {}
  }

  /// Update display name for a chat (e.g. when opening from search with profile name).
  void updateChatName(String chatId, String displayName) {
    if (displayName.trim().isEmpty) return;
    final norm = _normId(chatId);
    final i = _chats.indexWhere((c) => _normId(c.id) == norm);
    if (i < 0) return;
    _chats[i] = _chats[i].copyWith(name: displayName.trim());
    _saveToStorage();
    try {
      if (!_chatsController.isClosed) _chatsController.add(chats);
    } catch (_) {}
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _currentChatId = null;
    _typingByChatId.clear();
    _onlineByUserId.clear();
    _lastSeenByUserId.clear();
    try {
      if (!_typingController.isClosed) _typingController.close();
    } catch (_) {}
  }

  /// Clear all chats and messages and wipe storage so the next login (possibly different account) does not see the previous account's data.
  Future<void> clearAllDataForLogout() async {
    _chats.clear();
    _messages.clear();
    _typingByChatId.clear();
    _chats.insert(0, createChatObject('group_global', 'Global Chat'));
    try {
      final chatsJson = jsonEncode(_chats.map((c) => c.toJson()).toList());
      final messagesJson = jsonEncode(<String, List<Map<String, dynamic>>>{});
      final prefs = await _prefs;
      final kChats = _keyChats;
      final kMsgs = _keyMessages;
      if (EncryptedLocalStore.instance.isReady) {
        await EncryptedLocalStore.instance.setString(kChats, chatsJson);
        await EncryptedLocalStore.instance.setString(kMsgs, messagesJson);
        await EncryptedLocalStore.instance.remove(_legacyKeyChats);
        await EncryptedLocalStore.instance.remove(_legacyKeyMessages);
      }
      await prefs.setString(kChats, chatsJson);
      await prefs.setString(kMsgs, messagesJson);
      await prefs.remove(_legacyKeyChats);
      await prefs.remove(_legacyKeyMessages);
      if (!_chatsController.isClosed) _chatsController.add(chats);
      if (!_messagesController.isClosed) _messagesController.add(Map.from(_messages));
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatService] clearAllDataForLogout failed: $e');
    }
  }

  /// Wipe persisted chat buckets for [accountEmail] plus legacy keys (used from [BondhuApp] logout when no [ChatService] instance).
  static Future<void> wipePersistedChatsForAccount(String? accountEmail) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = <String>{
      storageKeyChats(accountEmail),
      storageKeyMessages(accountEmail),
      _legacyKeyChats,
      _legacyKeyMessages,
    };
    try {
      if (EncryptedLocalStore.instance.isReady) {
        for (final k in keys) {
          await EncryptedLocalStore.instance.remove(k);
        }
      }
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatService] wipePersistedChatsForAccount failed: $e');
    }
  }

  static const String _legacyKeyChats = 'bondhu_chats';
  static const String _legacyKeyMessages = 'bondhu_messages';

  static String _normAccountId(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    if (e.isEmpty) return 'guest';
    return e.replaceAll(RegExp(r'[^a-z0-9@._-]'), '_');
  }

  static String storageKeyChats(String? email) => 'bondhu_chats_v2_${_normAccountId(email)}';
  static String storageKeyMessages(String? email) => 'bondhu_messages_v2_${_normAccountId(email)}';

  String get _keyChats => storageKeyChats(_userEmail);
  String get _keyMessages => storageKeyMessages(_userEmail);

  /// Per-account cloud message backup (encrypted copies in Supabase). Migrates one-time global pref to this account.
  static Future<bool> cloudMessageBackupEnabledFor(String? accountEmail) async {
    final prefs = await SharedPreferences.getInstance();
    final e = (accountEmail ?? '').trim().toLowerCase();
    if (e.isEmpty) return prefs.getBool('bondhu_cloud_message_backup') ?? true;
    final k = 'bondhu_cloud_msg_v1_$e';
    if (prefs.containsKey(k)) return prefs.getBool(k) ?? true;
    final legacy = prefs.getBool('bondhu_cloud_message_backup');
    if (legacy != null) {
      await prefs.setBool(k, legacy);
      await prefs.remove('bondhu_cloud_message_backup');
      return legacy;
    }
    return true;
  }

  static Future<void> setCloudMessageBackupFor(String? accountEmail, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final e = (accountEmail ?? '').trim().toLowerCase();
    if (e.isEmpty) {
      await prefs.setBool('bondhu_cloud_message_backup', value);
      return;
    }
    await prefs.setBool('bondhu_cloud_msg_v1_$e', value);
  }

  Future<void> _loadFromStorage() async {
    try {
      // Reset in-memory state first so account switching on same device
      // never shows previous account data while loading.
      _chats.clear();
      _messages.clear();

      String? chatsJson;
      String? messagesJson;
      var loadedFromLegacy = false;

      if (EncryptedLocalStore.instance.isReady) {
        chatsJson = await EncryptedLocalStore.instance.getString(_keyChats);
        messagesJson = await EncryptedLocalStore.instance.getString(_keyMessages);
      }
      final prefs = await _prefs;
      chatsJson ??= prefs.getString(_keyChats);
      messagesJson ??= prefs.getString(_keyMessages);

      final v2Complete = chatsJson != null && messagesJson != null;
      if (!v2Complete) {
        String? legChats;
        String? legMsgs;
        if (EncryptedLocalStore.instance.isReady) {
          legChats = await EncryptedLocalStore.instance.getString(_legacyKeyChats);
          legMsgs = await EncryptedLocalStore.instance.getString(_legacyKeyMessages);
        }
        legChats ??= prefs.getString(_legacyKeyChats);
        legMsgs ??= prefs.getString(_legacyKeyMessages);
        if (legChats != null && legMsgs != null) {
          chatsJson = legChats;
          messagesJson = legMsgs;
          loadedFromLegacy = true;
        }
      }

      if (chatsJson != null) {
        final list = jsonDecode(chatsJson) as List<dynamic>?;
        if (list != null) {
          _chats.clear();
          for (final e in list) {
            if (e is Map<String, dynamic>) _chats.add(ChatItem.fromJson(e));
          }
        }
      }
      if (messagesJson != null) {
        final map = jsonDecode(messagesJson) as Map<String, dynamic>?;
        if (map != null) {
          _messages.clear();
          for (final entry in map.entries) {
            final list = entry.value as List<dynamic>?;
            if (list != null) {
              _messages[entry.key] = list
                  .map((e) => e is Map<String, dynamic>
                      ? ChatMessage.fromJson(e)
                      : null)
                  .whereType<ChatMessage>()
                  .toList();
            }
          }
        }
      }
      if (loadedFromLegacy) {
        await _saveToStorage();
        if (EncryptedLocalStore.instance.isReady) {
          await EncryptedLocalStore.instance.remove(_legacyKeyChats);
          await EncryptedLocalStore.instance.remove(_legacyKeyMessages);
        }
        final prefs2 = await _prefs;
        await prefs2.remove(_legacyKeyChats);
        await prefs2.remove(_legacyKeyMessages);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatService] _loadFromStorage failed: $e');
    }
  }

  Future<SharedPreferences> get _prefs async =>
      await SharedPreferences.getInstance();

  static const String _wipeDoneKey = 'bondhu_plaintext_wipe_done';

  Future<void> _saveToStorage() async {
    try {
      final chatsJson = jsonEncode(_chats.map((c) => c.toJson()).toList());
      final msgMap = <String, List<Map<String, dynamic>>>{};
      for (final e in _messages.entries) {
        msgMap[e.key] = e.value.map((m) => m.toJson()).toList();
      }
      final messagesJson = jsonEncode(msgMap);
      final prefs = await _prefs;
      if (EncryptedLocalStore.instance.isReady) {
        await EncryptedLocalStore.instance.setString(_keyChats, chatsJson);
        await EncryptedLocalStore.instance.setString(_keyMessages, messagesJson);
        // One-time wipe: remove plaintext copy from SharedPreferences after encrypted store has data.
        if (prefs.getBool(_wipeDoneKey) != true) {
          await prefs.remove(_keyChats);
          await prefs.remove(_keyMessages);
          await prefs.remove(_legacyKeyChats);
          await prefs.remove(_legacyKeyMessages);
          await prefs.setBool(_wipeDoneKey, true);
        }
      } else {
        await prefs.setString(_keyChats, chatsJson);
        await prefs.setString(_keyMessages, messagesJson);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatService] _saveToStorage failed: $e');
    }
  }
}
