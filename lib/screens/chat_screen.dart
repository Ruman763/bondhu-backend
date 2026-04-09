import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import '../config/app_config.dart';
import 'package:record/record.dart';
import '../design_tokens.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:speech_to_text/speech_to_text.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:translator_plus/translator_plus.dart';
import '../services/app_language_service.dart';
import '../services/supabase_service.dart';
import '../services/block_service.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/chat_theme_service.dart';
import '../services/mood_status_service.dart';
import '../services/nickname_service.dart';
import '../services/chat_notes_service.dart';
import '../services/draft_service.dart';
import '../services/pinned_message_service.dart';
import '../services/reply_later_service.dart';
import '../services/schedule_message_service.dart';
import '../services/starred_message_service.dart';
import '../services/voice_transcription_service.dart';
import '../services/chat_folder_service.dart';
import '../widgets/bondhu_app_logo.dart';
import 'chat_info_screen.dart';

/// Dedicated screen for a single conversation.
/// Matches bondhu-v2 ChatView.vue conversation panel exactly.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chat,
    this.chatService,
    this.callService,
    this.currentUserEmail,
    this.currentUserName,
    required this.userName,
    required this.userAvatarUrl,
    bool? isDark,
    this.onNavigateToChat,
  }) : isDark = isDark ?? true;

  final ChatItem chat;
  final ChatService? chatService;
  final CallService? callService;
  final String? currentUserEmail;
  final String? currentUserName;
  final String? userName;
  final String? userAvatarUrl;
  final bool isDark;
  /// When navigating to another chat (e.g. from Reply later list). Pops this screen then opens the chat.
  final void Function(String chatId)? onNavigateToChat;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _voiceButtonKey = GlobalKey();
  final _addButtonKey = GlobalKey();
  bool _addDrawerOpen = false;
  bool _showEmojiPicker = false;
  bool _hasText = false;
  ConnectionStatus _connectionStatus = ConnectionStatus.connecting;
  List<ChatMessage> _messages = [];
  StreamSubscription<Map<String, List<ChatMessage>>>? _messagesSub;
  StreamSubscription<ConnectionStatus>? _statusSub;
  VoidCallback? _presenceListener;
  VoidCallback? _themeListener;
  VoidCallback? _pinnedListener;
  Timer? _draftDebounceTimer;
  String _chatThemeKey = kChatThemeNone;
  late final String _chatId;
  /// Message being replied to; shown as preview above input.
  ChatMessage? _replyToMessage;
  /// When true, next sent message is marked "No rush" for the receiver.
  bool _noRush = false;
  /// Inline translations per message id (WeChat-style: show below original).
  Map<String, String> _messageTranslations = {};
  Map<String, bool> _messageTranslating = {};

  String get _statusText {
    final svc = widget.chatService;
    final chat = widget.chat;
    if (_isTyping) return AppLanguageService.instance.t('typing');
    if (!chat.isGroup && !chat.isGlobal && svc != null) {
      final peerId = chat.id;
      if (svc.isUserOnline(peerId)) return AppLanguageService.instance.t('online');
      final lastSeen = svc.getLastSeen(peerId) ?? svc.getPeerLastMessageTime(_chatId);
      if (lastSeen != null) return _formatLastSeen(lastSeen);
      return AppLanguageService.instance.t('last_seen_recently');
    }
    final base = switch (_connectionStatus) {
      ConnectionStatus.connected => AppLanguageService.instance.t('online'),
      ConnectionStatus.reconnecting => AppLanguageService.instance.t('reconnecting'),
      ConnectionStatus.connecting => AppLanguageService.instance.t('connecting'),
    };
    if (kDebugMode && _connectionStatus != ConnectionStatus.connected) {
      try {
        final host = Uri.parse(kChatServerUrl).host;
        return '$base ($host)';
      } catch (_) {}
    }
    return base;
  }

  String _formatLastSeen(DateTime at) {
    final t = AppLanguageService.instance.t;
    final now = DateTime.now();
    final diff = now.difference(at);
    if (diff.inMinutes < 1) return t('last_seen_recently');
    if (diff.inMinutes < 60) return t('last_seen_minutes_ago').replaceAll('%s', '${diff.inMinutes}');
    if (diff.inHours < 24) return t('last_seen_hours_ago').replaceAll('%s', '${diff.inHours}');
    final today = DateTime(now.year, now.month, now.day);
    final atDate = DateTime(at.year, at.month, at.day);
    if (atDate == today) {
      final timeStr = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
      return t('last_seen_today_at').replaceAll('%s', timeStr);
    }
    if (today.difference(atDate).inDays == 1) return t('last_seen_yesterday');
    return t('last_seen_recently');
  }

  StreamSubscription<Map<String, bool>>? _typingSub;
  Timer? _messagesDebounceTimer;
  bool _isTyping = false;
  bool _showScrollToBottom = false;
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  /// Text already in the input when voice-to-text started; we show prefix + latest recognized words to avoid duplicates.
  String _voiceToTextPrefix = '';
  bool _isRecordingVoiceMessage = false;
  AudioRecorder? _voiceRecorder;
  String? _voiceRecordPath;
  int _voiceRecordSeconds = 0;
  Timer? _voiceRecordTimer;

  /// In-chat voice message playback (single player shared by all bubbles).
  AudioPlayer? _voiceMessagePlayer;
  String? _playingVoiceMessageId;
  Duration _voicePosition = Duration.zero;
  Duration? _voiceDuration;

  @override
  void initState() {
    super.initState();
    _messageTranslations = <String, String>{};
    _messageTranslating = <String, bool>{};
    _chatId = widget.chat.id;
    widget.chatService?.setCurrentChatId(_chatId);
    final cs = widget.chatService;
    if (cs != null && !widget.chat.isGlobal && !widget.chat.isGroup) {
      unawaited(cs.syncChatFromCloud(_chatId));
    }
    NicknameService.instance.load();
    MoodStatusService.instance.load();
    _loadMessages();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        final list = widget.chatService?.getMessages(_chatId) ?? [];
        final myIds = list.where((m) => m.isMe).map((m) => m.id).toList();
        if (myIds.isNotEmpty) widget.chatService?.markRead(_chatId, myIds);
      });
    });
    final svc = widget.chatService;
    if (svc != null) {
      _connectionStatus = svc.isConnected ? ConnectionStatus.connected : ConnectionStatus.connecting;
      _isTyping = svc.isTyping(_chatId);
      // Debounce stream updates to reduce rebuilds and framedrop
      _messagesSub = svc.messagesStream.listen(
        (_) {
          if (!mounted) return;
          _messagesDebounceTimer?.cancel();
          _messagesDebounceTimer = Timer(const Duration(milliseconds: 80), () {
            if (!mounted) return;
            final service = svc;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final newList = List<ChatMessage>.from(service.getMessages(_chatId));
              setState(() => _messages = newList);
              _scrollToBottom();
            });
          });
        },
        onError: (e, st) {
          if (kDebugMode) debugPrint('[ChatScreen] messagesStream error: $e\n$st');
        },
        cancelOnError: false,
      );
      _statusSub = svc.connectionStatusStream.listen(
        (status) {
          if (!mounted || _connectionStatus == status) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _connectionStatus = status);
          });
        },
        onError: (e, st) {
          if (kDebugMode) debugPrint('[ChatScreen] connectionStatusStream error: $e\n$st');
        },
        cancelOnError: false,
      );
      _typingSub = svc.typingStream.listen(
        (_) {
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final typing = svc.isTyping(_chatId);
            if (typing != _isTyping) setState(() => _isTyping = typing);
          });
        },
        onError: (e, st) {
          if (kDebugMode) debugPrint('[ChatScreen] typingStream error: $e\n$st');
        },
        cancelOnError: false,
      );
      _presenceListener = () {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      };
      svc.presenceNotifier.addListener(_presenceListener!);
    }
    final draft = DraftService.instance.getDraft(_chatId);
    if (draft.isNotEmpty) {
      _messageController.text = draft;
      _hasText = true;
    }
    ChatThemeService.instance.getChatBackground(_chatId).then((k) {
      if (mounted) setState(() => _chatThemeKey = k);
    });
    _themeListener = () {
      if (!mounted) return;
      ChatThemeService.instance.getChatBackground(_chatId).then((k) {
        if (mounted) setState(() => _chatThemeKey = k);
      });
    };
    ChatThemeService.instance.version.addListener(_themeListener!);
    _pinnedListener = () {
      if (mounted) setState(() {});
    };
    PinnedMessageService.instance.version.addListener(_pinnedListener!);
    _scrollController.addListener(_onScroll);

    _voiceMessagePlayer = AudioPlayer();
    _voiceMessagePlayer!.onPositionChanged.listen((Duration d) {
      if (mounted) setState(() => _voicePosition = d);
    });
    _voiceMessagePlayer!.onDurationChanged.listen((Duration d) {
      if (mounted) setState(() => _voiceDuration = d);
    });
    _voiceMessagePlayer!.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingVoiceMessageId = null;
          _voicePosition = Duration.zero;
        });
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.offset >= _scrollController.position.maxScrollExtent - 120;
    if (atBottom != !_showScrollToBottom) setState(() => _showScrollToBottom = !atBottom);
  }

  /// Build list of items: date separators + messages. Pinned messages first, then by date.
  List<_ChatListItem> _buildChatListItems() {
    final pinnedIds = PinnedMessageService.instance.getPinned(_chatId).toList();
    final pinnedSet = pinnedIds.toSet();
    final sorted = List<ChatMessage>.from(_messages);
    sorted.sort((a, b) {
      final aPinned = pinnedSet.contains(a.id);
      final bPinned = pinnedSet.contains(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      if (aPinned && bPinned) {
        final ai = pinnedIds.indexOf(a.id);
        final bi = pinnedIds.indexOf(b.id);
        return ai.compareTo(bi);
      }
      return 0;
    });
    final list = <_ChatListItem>[];
    String? lastDate;
    for (final msg in sorted) {
      final dateLabel = _formatDateLabel(msg.date);
      if (dateLabel != null && dateLabel != lastDate) {
        list.add(_ChatListItem(dateLabel: dateLabel));
        lastDate = dateLabel;
      }
      list.add(_ChatListItem(message: msg));
    }
    return list;
  }

  static String? _formatDateLabel(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return 'Today';
    DateTime? d = DateTime.tryParse(isoDate);
    if (d == null) return 'Today';
    if (d.isUtc) d = d.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(d.year, d.month, d.day);
    if (msgDay == today) return 'Today';
    if (msgDay == yesterday) return 'Yesterday';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  void _loadMessages() {
    final svc = widget.chatService;
    if (svc != null) {
      setState(() => _messages = List.from(svc.getMessages(_chatId)));
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        pos,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _messagesDebounceTimer?.cancel();
    _messagesDebounceTimer = null;
    _voiceRecordTimer?.cancel();
    _voiceRecorder?.dispose();
    widget.chatService?.setCurrentChatId(null);
    _messagesSub?.cancel();
    _messagesSub = null;
    _statusSub?.cancel();
    _statusSub = null;
    if (_presenceListener != null) {
      widget.chatService?.presenceNotifier.removeListener(_presenceListener!);
      _presenceListener = null;
    }
    if (_themeListener != null) {
      ChatThemeService.instance.version.removeListener(_themeListener!);
      _themeListener = null;
    }
    if (_pinnedListener != null) {
      PinnedMessageService.instance.version.removeListener(_pinnedListener!);
      _pinnedListener = null;
    }
    _draftDebounceTimer?.cancel();
    _draftDebounceTimer = null;
    _typingSub?.cancel();
    _typingSub = null;
    _voiceMessagePlayer?.stop();
    _voiceMessagePlayer?.dispose();
    _voiceMessagePlayer = null;
    DraftService.instance.setDraft(_chatId, _messageController.text);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Play or pause a voice message. Only one plays at a time.
  Future<void> _playPauseVoiceMessage(String messageId, String audioUrl) async {
    if (audioUrl.isEmpty || _voiceMessagePlayer == null) return;
    if (_playingVoiceMessageId == messageId) {
      await _voiceMessagePlayer!.pause();
      if (mounted) setState(() => _playingVoiceMessageId = null);
      return;
    }
    await _voiceMessagePlayer!.stop();
    try {
      await _voiceMessagePlayer!.setSource(UrlSource(audioUrl));
      await _voiceMessagePlayer!.resume();
      if (mounted) {
        setState(() {
          _playingVoiceMessageId = messageId;
          _voicePosition = Duration.zero;
          _voiceDuration = null;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatScreen] Voice play error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLanguageService.instance.t('something_went_wrong')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static String _formatVoiceDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Voice message bubble: play/pause, progress bar, duration. Tapping play/pause or bar seeks.
  Widget _buildVoiceMessageBubble(BuildContext context, ChatMessage msg, String audioUrl, bool isDark) {
    final isPlaying = _playingVoiceMessageId == msg.id;
    final position = isPlaying ? _voicePosition : Duration.zero;
    final duration = isPlaying ? _voiceDuration : null;
    final total = duration ?? Duration.zero;
    final progress = total.inMilliseconds > 0
        ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final iconColor = msg.isMe ? Colors.black87 : (isDark ? const Color(0xFFE4E4E7) : const Color(0xFF18181B));
    const bubbleMinWidth = 200.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: audioUrl.isEmpty
            ? null
            : () => _playPauseVoiceMessage(msg.id, audioUrl),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minWidth: bubbleMinWidth),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: audioUrl.isEmpty ? null : () => _playPauseVoiceMessage(msg.id, audioUrl),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: msg.isMe
                          ? Colors.black.withValues(alpha: 0.08)
                          : BondhuTokens.primary.withValues(alpha: isDark ? 0.2 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 28,
                      color: msg.isMe ? Colors.black87 : BondhuTokens.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLanguageService.instance.t('voice_message_tap_play'),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: iconColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    isPlaying && total.inMilliseconds > 0
                        ? SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              trackHeight: 4,
                              activeTrackColor: msg.isMe ? Colors.black54 : BondhuTokens.primary,
                              inactiveTrackColor: msg.isMe
                                  ? Colors.black.withValues(alpha: 0.12)
                                  : (isDark ? Colors.white.withValues(alpha: 0.15) : BondhuTokens.primary.withValues(alpha: 0.2)),
                              thumbColor: msg.isMe ? Colors.black87 : BondhuTokens.primary,
                            ),
                            child: Slider(
                              value: position.inMilliseconds.clamp(0, total.inMilliseconds).toDouble(),
                              min: 0,
                              max: total.inMilliseconds.toDouble(),
                              onChanged: (v) {
                                _voiceMessagePlayer?.seek(Duration(milliseconds: v.round()));
                              },
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: msg.isMe
                                  ? Colors.black.withValues(alpha: 0.12)
                                  : (isDark ? Colors.white.withValues(alpha: 0.15) : BondhuTokens.primary.withValues(alpha: 0.2)),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                msg.isMe ? Colors.black54 : BondhuTokens.primary,
                              ),
                              minHeight: 4,
                            ),
                          ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatVoiceDuration(position)} / ${_formatVoiceDuration(total)}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: msg.isMe ? Colors.black54 : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sendText() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final svc = widget.chatService;
    _messageController.clear();
    if (_hasText) {
      _hasText = false;
      setState(() {});
    }
    final replyTo = _replyToMessage;
    if (replyTo != null) {
      _replyToMessage = null;
      setState(() {});
    }
    final noRushSent = _noRush;
    svc?.sendMessage(
      _chatId,
      text,
      'text',
      author: widget.currentUserName ?? widget.userName,
      replyToId: replyTo?.id,
      replyToText: replyTo?.text,
      noRush: noRushSent,
    );
    DraftService.instance.clearDraft(_chatId);
    if (noRushSent) setState(() => _noRush = false);
    svc?.emitTyping(_chatId, false);
    _scrollToBottom();
    if (svc != null && !svc.isConnected && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('message_will_send_when_online')),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return Scaffold(
      backgroundColor: isDark ? BondhuTokens.bgDark : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, isDark),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _buildChatBackground(isDark),
                  ),
                  RepaintBoundary(
                    child: Builder(
                      builder: (ctx) {
                        final chatItems = _messages.isEmpty ? <_ChatListItem>[] : _buildChatListItems();
                        return ListView.builder(
                          controller: _scrollController,
                          cacheExtent: 500,
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: true,
                          itemExtent: null,
                          padding: EdgeInsets.symmetric(
                            horizontal: BondhuTokens.responsive3(context, 16.0, 16.0, 24.0),
                            vertical: 16,
                          ),
                          itemCount: _messages.isEmpty ? 1 : chatItems.length,
                          itemBuilder: (context, i) {
                            if (_messages.isEmpty) {
                              return RepaintBoundary(
                                child: _buildEmptyState(context, isDark),
                              );
                            }
                            if (i < 0 || i >= chatItems.length) {
                              return const SizedBox.shrink();
                            }
                            final item = chatItems[i];
                            if (item.isDateSeparator) {
                              return RepaintBoundary(
                                key: ValueKey('date_${item.dateLabel}'),
                                child: _dateSeparator(item.dateLabel!),
                              );
                            }
                            final msg = item.message;
                            if (msg == null) return const SizedBox.shrink();
                            return RepaintBoundary(
                              key: ValueKey(msg.id),
                              child: GestureDetector(
                                onLongPress: () => _showMessageOptions(context, isDark, msg),
                                child: _messageBubble(context, msg, isDark),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  if (_showScrollToBottom) _buildScrollToBottomFab(context, isDark),
                ],
              ),
            ),
            if (_isTyping) _buildTypingBanner(context, isDark),
            _buildInputBar(context, isDark),
            if (_showEmojiPicker) _buildEmojiPicker(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBackground(bool isDark) {
    final dark = isDark == true;
    final moodKey = MoodStatusService.instance.currentMoodKey.value;
    double overlayAlpha = dark ? 0.45 : 0.35;
    if (moodKey == 'tired' || moodKey == 'need_support') {
      overlayAlpha = (overlayAlpha + 0.05).clamp(0.0, 0.7);
    } else if (moodKey == 'celebrating' || moodKey == 'happy') {
      overlayAlpha = (overlayAlpha - 0.05).clamp(0.1, 0.7);
    }
    final asset = chatThemeAsset(_chatThemeKey);
    if (asset == null) {
      return CustomPaint(
        painter: _ChatAreaPatternPainter(isDark: dark),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          asset,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => CustomPaint(
            painter: _ChatAreaPatternPainter(isDark: dark),
          ),
        ),
        Container(
          color: Colors.black.withValues(alpha: overlayAlpha),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    final chat = widget.chat;
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    final headerHeight = isWide ? 80.0 : 68.0;
    final avatarSize = isWide ? 42.0 : 36.0;
    final padH = isWide ? 20.0 : 14.0;
    final borderColor = (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.08 : 0.06);
    final headerGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0A0B),
              Color(0xFF121214),
              Color(0xFF0D0D0E),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF4FBF9),
              Color(0xFFE9F8F2),
              Color(0xFFF7FCFA),
            ],
          );

    return Container(
      height: headerHeight,
      padding: EdgeInsets.only(left: padH - 8, right: padH - 8, top: 8, bottom: 8),
      decoration: BoxDecoration(
        gradient: headerGradient,
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: isDark ? const Color(0xFFA1A1A1) : const Color(0xFF525252)),
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(8),
              minimumSize: const Size(40, 40),
            ),
          ),
          SizedBox(width: 4),
          chat.isGlobal
              ? BondhuAppLogo(size: avatarSize, circular: false, iconScale: 0.5)
              : _SafeAvatar(
                  url: chat.avatar,
                  size: avatarSize,
                  isDark: isDark,
                ),
          const SizedBox(width: 12),
          Expanded(
            child: ValueListenableBuilder<Map<String, String>>(
              valueListenable: NicknameService.instance.nicknames,
              builder: (context, nicknames, child) {
                return ValueListenableBuilder<String>(
                  valueListenable: MoodStatusService.instance.currentMoodKey,
                  builder: (context, moodKey, child) {
                    final moodLabel = MoodStatusService.instance.displayLabel;
                    final moodEmoji = MoodStatusService.instance.displayEmoji;
                    final statusLine = moodLabel.isEmpty ? _statusText : '$_statusText${moodEmoji.isNotEmpty ? ' · $moodEmoji ' : ''}$moodLabel';
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          NicknameService.instance.getDisplayName(chat),
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: isWide ? 16 : 15,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          statusLine,
                  style: GoogleFonts.inter(
                    fontSize: isWide ? 12 : 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xFF71717A) : const Color(0xFF64748B),
                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          _headerCallIcon(context, isDark, isVideo: false),
          _headerCallIcon(context, isDark, isVideo: true),
          _headerIcon(Icons.info_outline_rounded, isDark, onTap: () => _showChatInfoSheet(context, isDark)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    final isGlobal = widget.chat.id == 'group_global';
    final subColor = isDark ? const Color(0xFF71717A) : const Color(0xFF6B7280);
    final iconColor = isDark ? const Color(0xFF525252) : const Color(0xFF9CA3AF);
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            isGlobal
                ? const BondhuAppLogo(size: 80, circular: false, iconScale: 0.5)
                : Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 40,
                      color: iconColor,
                    ),
                  ),
            const SizedBox(height: 24),
            Text(
              isGlobal ? AppLanguageService.instance.t('global_chat') : AppLanguageService.instance.t('no_messages'),
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF18181B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isGlobal
                  ? AppLanguageService.instance.t('say_hello')
                  : AppLanguageService.instance.t('send_message_start'),
              style: GoogleFonts.inter(
                fontSize: 14,
                color: subColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollToBottomFab(BuildContext context, bool isDark) {
    return Positioned(
      right: 20,
      bottom: 100,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(28),
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        child: InkWell(
          onTap: () => _scrollToBottom(),
          borderRadius: BorderRadius.circular(28),
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 28,
              color: BondhuTokens.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypingBanner(BuildContext context, bool isDark) {
    final name = widget.chat.id == 'group_global' ? 'Someone' : widget.chat.name;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.8),
      child: Row(
        children: [
          Text(
            '$name is typing…',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: BondhuTokens.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) => Padding(
              key: ValueKey('typing_dot_$i'),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: BondhuTokens.primary,
                  shape: BoxShape.circle,
                ),
              ),
            )),
          ),
        ],
      ),
    );
  }

  /// Call buttons are disabled when socket is not connected or chat is global; tooltip explains why.
  Widget _headerCallIcon(BuildContext context, bool isDark, {required bool isVideo}) {
    final canCall = _connectionStatus == ConnectionStatus.connected && !widget.chat.isGlobal;
    final tooltip = widget.chat.isGlobal
        ? AppLanguageService.instance.t('calls_private_only')
        : _connectionStatus != ConnectionStatus.connected
            ? AppLanguageService.instance.t('call_not_ready')
            : null;
    final color = canCall
        ? (isDark ? const Color(0xFFA1A1A1) : const Color(0xFF525252))
        : (isDark ? const Color(0xFF525252) : const Color(0xFFA1A1A1));
    final icon = Icon(
      isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
      size: 22,
      color: color,
    );
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onCallTap(context, isDark, isVideo: isVideo),
        borderRadius: BorderRadius.circular(20),
        child: Padding(padding: const EdgeInsets.all(10), child: icon),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: child);
    }
    return child;
  }

  Widget _headerIcon(IconData icon, bool isDark, {VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () {},
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: isDark ? const Color(0xFFA1A1A1) : const Color(0xFF525252)),
        ),
      ),
    );
  }

  void _showChatInfoSheet(BuildContext context, bool isDark) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: false,
        builder: (_) => ChatInfoScreen(
          chat: widget.chat,
          isDark: isDark,
          onViewProfile: () {
            _showProfileSheet(context, isDark);
          },
          onSearchInConversation: () {
            _showSearchInConversation(context, isDark);
          },
          onMuteChanged: (muteMessages, muteCalls) =>
              widget.chatService?.setMuteSettings(widget.chat.id, muteMessages: muteMessages, muteCalls: muteCalls),
          onBlock: () async {
            await BlockService.instance.add(widget.chat.id);
            widget.chatService?.removeChat(widget.chat.id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'You blocked ${widget.chat.name}. You can unblock in Settings.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 14),
                  ),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          },
          onUnblock: () async {
            await BlockService.instance.remove(widget.chat.id);
            if (context.mounted) Navigator.of(context).pop();
          },
          isBlocked: BlockService.instance.isBlocked(widget.chat.id),
          onDeleteChat: () {
            widget.chatService?.removeChat(widget.chat.id);
            if (context.mounted) Navigator.pop(context);
          },
          onViewMedia: () {
            _showViewMedia(context, isDark);
          },
          onPinChat: (pinned) => widget.chatService?.setPinned(widget.chat.id, pinned),
          onFolderChanged: (folderName) {
            ChatFolderService.instance.setFolder(widget.chat.id, folderName);
            widget.chatService?.setFolder(widget.chat.id, folderName);
          },
          onClearChat: () {
            widget.chatService?.clearMessages(widget.chat.id);
            if (context.mounted) Navigator.pop(context);
          },
          onMarkUnread: () {
            widget.chatService?.markUnread(widget.chat.id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLanguageService.instance.t('marked_as_unread')), behavior: SnackBarBehavior.floating),
              );
            }
          },
          onArchive: () {
            widget.chatService?.setArchived(widget.chat.id, true);
            if (context.mounted) Navigator.pop(context);
          },
          onUnarchive: () {
            widget.chatService?.setArchived(widget.chat.id, false);
            if (context.mounted) Navigator.pop(context);
          },
          onSnooze: (duration) {
            widget.chatService?.setSnooze(widget.chat.id, duration);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
    );
  }

  Future<void> _showProfileSheet(BuildContext context, bool isDark) async {
    final chat = widget.chat;
    await ChatFolderService.instance.load();
    final folderName = chat.folder ?? ChatFolderService.instance.getFolder(chat.id);
    final audienceKey = audienceKeyFromFolder(folderName);
    final profile = await getProfileByUserId(chat.id);

    final displayName = profile?.effectiveName(audienceKey) ?? chat.name;
    final displayAvatar = profile?.effectiveAvatar(audienceKey) ?? chat.avatar ?? '';
    final displayBio = profile?.effectiveBio(audienceKey);

    if (!context.mounted) return;
    final surface = isDark ? const Color(0xFF0A0A0B) : const Color(0xFFF8F9FA);
    final cardBg = isDark ? const Color(0xFF161618) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111113);
    final textMuted = isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73);
    final isPrivate = !chat.isGlobal && chat.email != null && chat.email!.isNotEmpty;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(ctx).bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                if (audienceKey != kAudienceDefault) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: BondhuTokens.primary.withValues(alpha: isDark ? 0.2 : 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      audienceKey == kAudienceWork
                          ? AppLanguageService.instance.t('profile_view_work')
                          : AppLanguageService.instance.t('profile_view_personal'),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: BondhuTokens.primary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            BondhuTokens.primary.withValues(alpha: 0.4),
                            BondhuTokens.primary.withValues(alpha: 0.15),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: cardBg, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: displayAvatar.isNotEmpty
                            ? Image.network(
                                displayAvatar,
                                fit: BoxFit.cover,
                                errorBuilder: (_, Object error, StackTrace? stackTrace) => _profileAvatarPlaceholder(displayName, textMuted),
                              )
                            : _profileAvatarPlaceholder(displayName, textMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  displayName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    letterSpacing: -0.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (displayBio != null && displayBio.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      displayBio.trim(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: textMuted,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                if (chat.email != null && chat.email!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    chat.email!,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (isPrivate) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: BondhuTokens.primary.withValues(alpha: isDark ? 0.12 : 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: BondhuTokens.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded, size: 16, color: BondhuTokens.primary),
                        const SizedBox(width: 8),
                        Text(
                          AppLanguageService.instance.t('end_to_end_encrypted'),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: FilledButton.styleFrom(
                        backgroundColor: BondhuTokens.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        AppLanguageService.instance.t('done'),
                        style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileAvatarPlaceholder(String name, Color textMuted) {
    return Container(
      color: textMuted.withValues(alpha: 0.2),
      child: Center(
        child: Text(
          (name.isNotEmpty ? name[0] : '?').toUpperCase(),
          style: GoogleFonts.plusJakartaSans(fontSize: 36, fontWeight: FontWeight.w700, color: textMuted),
        ),
      ),
    );
  }

  void _showViewMedia(BuildContext context, bool isDark) {
    final images = _messages.where((m) => m.type == 'image').toList();
    final voice = _messages.where((m) => m.type == 'audio').toList();
    final files = _messages.where((m) => m.type == 'file').toList();
    final hasAny = images.isNotEmpty || voice.isNotEmpty || files.isNotEmpty;
    if (!hasAny) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguageService.instance.t('no_media_in_chat'),
            style: GoogleFonts.plusJakartaSans(fontSize: 14),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _MediaGalleryScreen(
          isDark: isDark,
          images: images,
          voiceMessages: voice,
          files: files,
          chatName: widget.chat.name,
          onPlayVoiceMessage: (messageId, audioUrl) {
            _playPauseVoiceMessage(messageId, audioUrl);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }


  static const List<String> _reactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '😡'];

  void _showEditMessageDialog(BuildContext context, bool isDark, ChatMessage msg) {
    final controller = TextEditingController(text: msg.text);
    final surface = isDark ? const Color(0xFF18181B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: Text(
          AppLanguageService.instance.t('edit_message'),
          style: TextStyle(color: textColor),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: AppLanguageService.instance.t('type_message'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLanguageService.instance.t('cancel')),
          ),
          TextButton(
            onPressed: () {
              final newText = controller.text.trim();
              if (newText.isNotEmpty && newText != msg.text) {
                widget.chatService?.editMessage(_chatId, msg.id, newText);
              }
              Navigator.pop(ctx);
            },
            child: Text(AppLanguageService.instance.t('save')),
          ),
        ],
      ),
    );
  }

  void _showStarWithLabel(BuildContext ctx, bool isDark, ChatMessage msg) {
    final surface = isDark ? const Color(0xFF18181B) : Colors.white;
    final t = AppLanguageService.instance.t;
    final labels = [
      (t('label_important'), 'Important'),
      (t('label_todo'), 'To do'),
      (t('label_later'), 'Later'),
    ];
    Navigator.pop(ctx);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                t('star_message'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_outline_rounded),
              title: Text(t('star_message')),
              onTap: () async {
                StarredMessageService.instance.add(_chatId, msg.id);
                await _appendMessageToChatNote(_chatId, msg.text, kNoteFolderDefault);
                if (!context.mounted) return;
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(t('saved_messages')),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              },
            ),
            ...labels.map((l) {
              final folder = l.$2 == 'Important' ? kNoteFolderImportant : l.$2 == 'To do' ? kNoteFolderTodo : kNoteFolderDefault;
              return ListTile(
                leading: const Icon(Icons.label_outline_rounded),
                title: Text(l.$1),
                onTap: () async {
                  StarredMessageService.instance.add(_chatId, msg.id, label: l.$2);
                  await _appendMessageToChatNote(_chatId, msg.text, folder);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${t('saved_messages')} · ${l.$1}'),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showMessageOptions(BuildContext context, bool isDark, ChatMessage msg) {
    final surface = isDark ? const Color(0xFF18181B) : Colors.white;
    final subColor = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E7EB),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Message options',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.15,
                  color: subColor,
                ),
              ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _reactionEmojis.map((emoji) {
                  return Material(
                    key: ValueKey('reaction_$emoji'),
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        widget.chatService?.setMessageReaction(_chatId, msg.id, emoji);
                        Navigator.pop(ctx);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          emoji,
                          style: TextStyle(
                            fontSize: 28,
                            color: msg.reaction == emoji ? null : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                _messageOptionTile(
                ctx,
                isDark,
                icon: Icons.reply_rounded,
                label: 'Reply',
                onTap: () {
                  setState(() => _replyToMessage = msg);
                  Navigator.pop(ctx);
                },
              ),
              if (msg.isMe && msg.type == 'text')
                _messageOptionTile(
                  ctx,
                  isDark,
                  icon: Icons.edit_outlined,
                  label: AppLanguageService.instance.t('edit_message'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditMessageDialog(context, isDark, msg);
                  },
                ),
              if (StarredMessageService.instance.isStarred(_chatId, msg.id))
                _messageOptionTile(
                  ctx,
                  isDark,
                  icon: Icons.bookmark_rounded,
                  label: AppLanguageService.instance.t('unstar_message'),
                  onTap: () {
                    StarredMessageService.instance.remove(_chatId, msg.id);
                    Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLanguageService.instance.t('unstar_message')),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                )
              else
                _messageOptionTile(
                  ctx,
                  isDark,
                  icon: Icons.bookmark_outline_rounded,
                  label: AppLanguageService.instance.t('star_message'),
                  onTap: () => _showStarWithLabel(ctx, isDark, msg),
                ),
              if (PinnedMessageService.instance.isPinned(_chatId, msg.id))
                _messageOptionTile(
                  ctx,
                  isDark,
                  icon: Icons.push_pin_rounded,
                  label: 'Unpin',
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    await PinnedMessageService.instance.unpin(_chatId, msg.id);
                    if (!context.mounted) return;
                    Navigator.pop(ctx);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLanguageService.instance.t('message_unpinned')),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                )
              else
                _messageOptionTile(
                  ctx,
                  isDark,
                  icon: Icons.push_pin_outlined,
                  label: 'Pin message',
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    final ok = await PinnedMessageService.instance.pin(_chatId, msg.id);
                    if (!context.mounted) return;
                    Navigator.pop(ctx);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok ? AppLanguageService.instance.t('message_pinned') : AppLanguageService.instance.t('max_pins_per_chat')),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                _messageOptionTile(
                  ctx,
                  isDark,
                  icon: Icons.schedule_rounded,
                  label: 'Reply later',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showReplyLaterPicker(context, isDark, msg);
                  },
                ),
                if (!widget.chat.isGroup && !widget.chat.isGlobal)
                  _messageOptionTile(
                    ctx,
                    isDark,
                    icon: Icons.hourglass_top_rounded,
                    label: _noRush ? 'No rush ✓ (next message)' : 'Send next as No rush',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _noRush = true);
                      Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Next message will be sent as "No rush"'),
                          behavior: SnackBarBehavior.floating,
                        ));
                      }
                    },
                  ),
                _messageOptionTile(
                  ctx,
                  isDark,
                  icon: Icons.copy_rounded,
                  label: AppLanguageService.instance.t('copy_text'),
                  onTap: () {
                  Clipboard.setData(ClipboardData(text: msg.text));
                  Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLanguageService.instance.t('copied')),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                },
              ),
              if (msg.type == 'audio')
                _messageOptionTile(
                  ctx,
                  isDark,
                  icon: Icons.text_snippet_rounded,
                  label: AppLanguageService.instance.t('transcribe_voice_to_text'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _transcribeVoiceMessage(context, isDark, msg);
                  },
                ),
              if (msg.type == 'text' && msg.text.trim().isNotEmpty) ...[
                if (_messageTranslations.containsKey(msg.id))
                  _messageOptionTile(
                    ctx,
                    isDark,
                    icon: Icons.visibility_off_rounded,
                    label: AppLanguageService.instance.t('hide_translation'),
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _messageTranslations.remove(msg.id);
                      });
                    },
                  )
                else
                  _messageOptionTile(
                    ctx,
                    isDark,
                    icon: Icons.translate_rounded,
                    label: AppLanguageService.instance.t('translate'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _translateMessageInline(context, msg);
                    },
                  ),
                if (_messageTranslations.containsKey(msg.id))
                  _messageOptionTile(
                    ctx,
                    isDark,
                    icon: Icons.copy_rounded,
                    label: AppLanguageService.instance.t('copy_translation'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Clipboard.setData(ClipboardData(text: _messageTranslations[msg.id] ?? ''));
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLanguageService.instance.t('copied')),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
              ],
              _messageOptionTile(
                ctx,
                isDark,
                icon: Icons.delete_outline_rounded,
                label: 'Delete for me',
                textColor: const Color(0xFFDC2626),
                onTap: () {
                  widget.chatService?.deleteMessage(_chatId, msg.id);
                  Navigator.pop(ctx);
                },
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: subColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _translateMessageInline(BuildContext context, ChatMessage msg) async {
    final targetLang = AppLanguageService.instance.current == 'bn' ? 'bn' : 'en';
    final originalText = msg.text.trim();
    if (originalText.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _messageTranslating[msg.id] = true;
    });
    try {
      final translator = GoogleTranslator();
      final translation = await translator.translate(
        originalText.length > 500 ? originalText.substring(0, 500) : originalText,
        to: targetLang,
      );
      if (!mounted) return;
      setState(() {
        _messageTranslating.remove(msg.id);
        _messageTranslations[msg.id] = translation.text;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messageTranslating.remove(msg.id);
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('translation_failed')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static String _formatScheduledTime(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final whenDay = DateTime(when.year, when.month, when.day);
    final timeStr = '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    if (whenDay == today) return timeStr;
    if (whenDay == today.add(const Duration(days: 1))) return '${AppLanguageService.instance.t('tomorrow')} $timeStr';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[when.month - 1]} ${when.day} $timeStr';
  }

  void _showScheduleMessageSheet(BuildContext context, bool isDark) {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('type_message_first')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final surface = isDark ? const Color(0xFF18181B) : Colors.white;
    final subColor = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280);
    final replyTo = _replyToMessage;
    void scheduleAt(DateTime when) async {
      HapticFeedback.selectionClick();
      final msg = ScheduledMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        chatId: _chatId,
        text: text,
        sendAtMs: when.millisecondsSinceEpoch,
        type: 'text',
        replyToId: replyTo?.id,
        replyToText: replyTo?.text,
      );
      await ScheduleMessageService.instance.add(msg);
      _messageController.clear();
      if (_hasText) {
        _hasText = false;
        setState(() {});
      }
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final fmt = _formatScheduledTime(when);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('scheduled_for').replaceAll('%s', fmt)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppLanguageService.instance.t('schedule_message'), style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF111113))),
              const SizedBox(height: 6),
              Text(text.length > 80 ? '${text.substring(0, 80)}…' : text, style: GoogleFonts.inter(fontSize: 13, color: subColor), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),
              _scheduleOption(ctx, isDark, 'In 1 hour', () => scheduleAt(DateTime.now().add(const Duration(hours: 1)))),
              _scheduleOption(ctx, isDark, 'In 3 hours', () => scheduleAt(DateTime.now().add(const Duration(hours: 3)))),
              _scheduleOption(ctx, isDark, 'Tomorrow 9:00', () {
                final t = DateTime.now();
                scheduleAt(DateTime(t.year, t.month, t.day + 1, 9, 0));
              }),
              _scheduleOption(ctx, isDark, 'Pick date & time', () async {
                final date = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 1)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (date == null || !context.mounted) return;
                final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                if (time == null || !context.mounted) return;
                scheduleAt(DateTime(date.year, date.month, date.day, time.hour, time.minute));
              }),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLanguageService.instance.t('cancel'), style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: subColor))),
            ],
          ),
        ),
      ),
    );
  }

  /// Appends a saved message to the Chat note folder (default, todo, or important).
  Future<void> _appendMessageToChatNote(String chatId, String messageText, String folder) async {
    if (messageText.trim().isEmpty) return;
    await ChatNotesService.instance.addEntry(chatId, folder, '• ${messageText.trim()}');
  }

  void _showChatNoteSheet(BuildContext context, bool isDark) async {
    await ChatNotesService.instance.load();
    if (!context.mounted) return;
    final surfaceColor = isDark ? BondhuTokens.surfaceDark : BondhuTokens.surfaceLight;
    final textColor = isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight;
    final mutedColor = isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight;
    final borderColor = isDark ? BondhuTokens.borderDark : BondhuTokens.borderLight;
    String selectedFolder = kNoteFolderDefault;
    final folderLabels = {
      kNoteFolderDefault: AppLanguageService.instance.t('profile_audience_default'),
      kNoteFolderTodo: AppLanguageService.instance.t('label_todo'),
      kNoteFolderImportant: AppLanguageService.instance.t('label_important'),
    };
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          height: MediaQuery.of(ctx).size.height * 0.88,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(BondhuTokens.radius2xl)),
          ),
          child: SafeArea(
            top: false,
            child: StatefulBuilder(
              builder: (ctx, setSheetState) {
                final entries = ChatNotesService.instance.getEntries(_chatId, selectedFolder);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Container(
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color: mutedColor.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(
                              foregroundColor: BondhuTokens.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(AppLanguageService.instance.t('cancel'), style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w400)),
                          ),
                          const Spacer(),
                          Text(
                            AppLanguageService.instance.t('chat_note'),
                            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(
                              foregroundColor: BondhuTokens.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(AppLanguageService.instance.t('done'), style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 12),
                      child: Text(
                        AppLanguageService.instance.t('chat_note_hint'),
                        style: GoogleFonts.inter(fontSize: 13, color: mutedColor, height: 1.3),
                      ),
                    ),
                    // Folder chips: Default | To do | Important
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: kNoteFolders.map((folder) {
                          final isSelected = selectedFolder == folder;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setSheetState(() => selectedFolder = folder);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected ? BondhuTokens.primary.withValues(alpha: isDark ? 0.25 : 0.15) : (isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF4F4F5)),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? BondhuTokens.primary : Colors.transparent,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    folderLabels[folder] ?? folder,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                      color: isSelected ? BondhuTokens.primary : textColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Divider(height: 1, color: borderColor),
                    Expanded(
                      child: entries.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  AppLanguageService.instance.t('notes_placeholder'),
                                  style: GoogleFonts.inter(fontSize: 15, color: mutedColor),
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                              itemCount: entries.length,
                              itemBuilder: (_, index) {
                                final line = entries[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          line,
                                          style: GoogleFonts.inter(fontSize: 15, height: 1.45, color: textColor),
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.close_rounded, size: 18, color: mutedColor),
                                        onPressed: () async {
                                          await ChatNotesService.instance.removeEntry(_chatId, selectedFolder, index);
                                          if (ctx.mounted) setSheetState(() {});
                                        },
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _scheduleOption(BuildContext ctx, bool isDark, String label, VoidCallback onTap) {
    final textColor = isDark ? Colors.white : const Color(0xFF111113);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(children: [Icon(Icons.schedule_rounded, size: 20, color: BondhuTokens.primary), const SizedBox(width: 12), Text(label, style: GoogleFonts.inter(fontSize: 15, color: textColor))]),
        ),
      ),
    );
  }

  void _showReplyLaterPicker(BuildContext context, bool isDark, ChatMessage msg) {
    final chatName = NicknameService.instance.getDisplayName(widget.chat);
    final preview = msg.text.length > 50 ? '${msg.text.substring(0, 50)}…' : msg.text;
    int remindAtMs(int hours) => DateTime.now().add(Duration(hours: hours)).millisecondsSinceEpoch;
    DateTime tomorrow9() {
      final t = DateTime.now();
      return DateTime(t.year, t.month, t.day + 1, 9, 0);
    }
    DateTime tonight21() {
      final t = DateTime.now();
      return DateTime(t.year, t.month, t.day, 21, 0);
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Remind me to reply',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight),
              ),
              const SizedBox(height: 8),
              Text(
                preview,
                style: GoogleFonts.inter(fontSize: 13, color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              _replyLaterOption(ctx, isDark, 'In 1 hour', () async {
                Navigator.pop(ctx);
                await ReplyLaterService.instance.add(ReplyLaterReminder(chatId: _chatId, messageId: msg.id, remindAtMs: remindAtMs(1), previewText: preview, chatName: chatName));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder set for 1 hour'), behavior: SnackBarBehavior.floating));
              }),
              _replyLaterOption(ctx, isDark, 'In 3 hours', () async {
                Navigator.pop(ctx);
                await ReplyLaterService.instance.add(ReplyLaterReminder(chatId: _chatId, messageId: msg.id, remindAtMs: remindAtMs(3), previewText: preview, chatName: chatName));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder set for 3 hours'), behavior: SnackBarBehavior.floating));
              }),
              _replyLaterOption(ctx, isDark, 'Tonight (9 PM)', () async {
                Navigator.pop(ctx);
                await ReplyLaterService.instance.add(ReplyLaterReminder(chatId: _chatId, messageId: msg.id, remindAtMs: tonight21().millisecondsSinceEpoch, previewText: preview, chatName: chatName));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder set for tonight'), behavior: SnackBarBehavior.floating));
              }),
              _replyLaterOption(ctx, isDark, 'Tomorrow (9 AM)', () async {
                Navigator.pop(ctx);
                await ReplyLaterService.instance.add(ReplyLaterReminder(chatId: _chatId, messageId: msg.id, remindAtMs: tomorrow9().millisecondsSinceEpoch, previewText: preview, chatName: chatName));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder set for tomorrow'), behavior: SnackBarBehavior.floating));
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReplyLaterList(BuildContext context, bool isDark) async {
    await ReplyLaterService.instance.load();
    if (!context.mounted) return;
    final textPrimary = isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight;
    final textMuted = isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.92,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 20),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          'Reply later',
                          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: IconButton.styleFrom(foregroundColor: textMuted),
                    ),
                  ],
                ),
                Expanded(
                  child: ValueListenableBuilder<List<ReplyLaterReminder>>(
                    valueListenable: ReplyLaterService.instance.reminders,
                    builder: (context, list, child) {
                      if (list.isEmpty) {
                        return ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                          children: [
                            Icon(Icons.schedule_rounded, size: 56, color: textMuted.withValues(alpha: 0.7)),
                            const SizedBox(height: 16),
                            Text(
                              'No reminders yet',
                              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Long-press a message → Reply later to add one',
                              style: GoogleFonts.inter(fontSize: 14, color: textMuted),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        );
                      }
                      final now = DateTime.now().millisecondsSinceEpoch;
                      final due = list.where((r) => r.remindAtMs <= now).toList();
                      final upcoming = list.where((r) => r.remindAtMs > now).toList();
                      return ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                    if (due.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: Text('Due', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: BondhuTokens.primary)),
                      ),
                      ...due.map((r) => _reminderTile(ctx, isDark, r, true, textPrimary, textMuted)),
                    ],
                    if (upcoming.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.fromLTRB(20, due.isNotEmpty ? 16 : 8, 20, 4),
                        child: Text('Upcoming', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textMuted)),
                      ),
                      ...upcoming.map((r) => _reminderTile(ctx, isDark, r, false, textPrimary, textMuted)),
                    ],
                  ],
                );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reminderTile(BuildContext context, bool isDark, ReplyLaterReminder r, bool isDue, Color textPrimary, Color textMuted) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          widget.onNavigateToChat?.call(r.chatId);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 22,
                color: isDue ? BondhuTokens.primary : textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.chatName ?? r.chatId,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.previewText,
                      style: GoogleFonts.inter(fontSize: 13, color: textMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ReplyLaterService.formatWhen(r.remindAtMs),
                      style: GoogleFonts.inter(fontSize: 11, color: textMuted.withValues(alpha: 0.9)),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () async {
                  HapticFeedback.selectionClick();
                  await ReplyLaterService.instance.remove(r.chatId, r.messageId);
                },
                style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  foregroundColor: textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _replyLaterOption(BuildContext ctx, bool isDark, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 22, color: BondhuTokens.primary),
              const SizedBox(width: 14),
              Text(label, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageOptionTile(
    BuildContext ctx,
    bool isDark, {
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color? textColor,
  }) {
    final color = textColor ?? (isDark ? Colors.white : const Color(0xFF18181B));
    final iconColor = textColor ?? (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: iconColor),
              const SizedBox(width: 16),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSearchInConversation(BuildContext context, bool isDark) {
    final query = ValueNotifier<String>('');

    showDialog<void>(
      context: context,
      builder: (ctx) => ValueListenableBuilder<String>(
        valueListenable: query,
        builder: (context, q, _) {
          final list = q.trim().isEmpty ? <ChatMessage>[] : _messages.where((m) => m.text.toLowerCase().contains(q.trim().toLowerCase())).toList();
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              AppLanguageService.instance.t('search_in_conversation'),
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF18181B),
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (v) => query.value = v,
                    decoration: InputDecoration(
                      hintText: AppLanguageService.instance.t('type_to_search'),
                      hintStyle: TextStyle(color: isDark ? const Color(0xFF71717A) : const Color(0xFF6B7280)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF27272A) : const Color(0xFFF9FAFB),
                    ),
                    style: TextStyle(color: isDark ? Colors.white : const Color(0xFF111827)),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 280,
                    child: list.isEmpty
                          ? Center(
                              child: Text(
                                q.trim().isEmpty ? AppLanguageService.instance.t('search_messages') : AppLanguageService.instance.t('no_matches'),
                                style: TextStyle(fontSize: 14, color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280)),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: list.length,
                              itemBuilder: (context, i) {
                                final m = list[i];
                                return ListTile(
                                  key: ValueKey(m.id),
                                  dense: true,
                                  title: Text(
                                    m.text.length > 80 ? '${m.text.substring(0, 80)}...' : m.text,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: isDark ? const Color(0xFFE4E4E7) : const Color(0xFF374151),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${m.time}${m.isMe ? " · You" : ""}',
                                    style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF71717A) : const Color(0xFF9CA3AF)),
                                  ),
                                  onTap: () => Navigator.pop(ctx),
                                );
                              },
                            ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLanguageService.instance.t('close'), style: GoogleFonts.inter(color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280))),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dateSeparator(String label) {
    final isDark = widget.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withValues(alpha: 0.4) : const Color(0xFFD1D5DB),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE5E7EB),
              width: 1,
            ),
          ),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.15,
              color: isDark ? const Color(0xFFD4D4D8) : const Color(0xFF4B5563),
            ),
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder({required bool isMe, required bool isDark, String? imageUrl, VoidCallback? onTap}) {
    final color = isMe ? Colors.black87 : (isDark ? const Color(0xFFE4E4E7) : const Color(0xFF18181B));
    final hasTap = onTap != null || (imageUrl != null && imageUrl.startsWith('http'));
    final label = hasTap ? 'Tap to open image' : 'Image';
    final body = Container(
      width: 220,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasTap ? Icons.open_in_new_rounded : Icons.image_not_supported_outlined,
            size: 28,
            color: color.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 14, color: color.withValues(alpha: 0.8)),
            ),
          ),
        ],
      ),
    );
    if (hasTap) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (onTap != null) {
              onTap();
            } else if (imageUrl != null && imageUrl.startsWith('http')) {
              final uri = Uri.tryParse(imageUrl);
              if (uri != null) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: body,
        ),
      );
    }
    return body;
  }

  Widget _messageBubble(BuildContext context, ChatMessage msg, bool isDark) {
    const radius = 20.0;
    const tailRadius = 4.0;
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    final type = msg.type;
    // Memoize expensive computations
    Widget content;
    if (type == 'image') {
      final rawUrl = msg.text.trim();
      final url = rawUrl.isEmpty
          ? ''
          : (rawUrl.startsWith('http') ? rawUrl : storageFileViewUrl(rawUrl));
      if (url.isNotEmpty) {
        content = GestureDetector(
          onTap: () => _showFullScreenImage(context, url, isDark),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              width: 220,
              height: 220,
              fit: BoxFit.cover,
              cacheWidth: 440,
              cacheHeight: 440,
              gaplessPlayback: true,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return SizedBox(
                  width: 220,
                  height: 220,
                  child: Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: msg.isMe ? Colors.black26 : BondhuTokens.primary.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                );
              },
              errorBuilder: (_, error, stackTrace) => _imagePlaceholder(
                isMe: msg.isMe,
                isDark: isDark,
                imageUrl: url,
                onTap: () => _showFullScreenImage(context, url, isDark),
              ),
            ),
          ),
        );
      } else {
        content = _imagePlaceholder(isMe: msg.isMe, isDark: isDark);
      }
    } else if (type == 'call') {
      final isVideo = msg.callType == 'video';
      content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isVideo ? Icons.videocam_rounded : Icons.call_rounded,
            size: 20,
            color: msg.isMe ? Colors.black87 : (isDark ? const Color(0xFFE4E4E7) : const Color(0xFF18181B)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              msg.text,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: msg.isMe ? Colors.black87 : (isDark ? const Color(0xFFE4E4E7) : const Color(0xFF18181B)),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else if (type == 'file' || type == 'audio') {
      final isAudio = type == 'audio';
      if (isAudio) {
        final audioUrl = msg.text.trim().isEmpty
            ? ''
            : (msg.text.startsWith('http') ? msg.text : storageFileViewUrl(msg.text));
        content = _buildVoiceMessageBubble(context, msg, audioUrl, isDark);
      } else {
        content = Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              final uri = Uri.tryParse(msg.text);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.insert_drive_file_rounded,
                    size: 24,
                    color: msg.isMe ? Colors.black87 : (isDark ? const Color(0xFFE4E4E7) : const Color(0xFF18181B)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      msg.text.length > 40 ? '${msg.text.substring(0, 40)}...' : msg.text,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: msg.isMe ? Colors.black : (isDark ? const Color(0xFFE4E4E7) : const Color(0xFF18181B)),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } else {
      // Text message: show original and optional WeChat-style translation below
      final messageId = msg.id;
      final translated = (messageId.isNotEmpty && _messageTranslations.containsKey(messageId))
          ? _messageTranslations[messageId]
          : null;
      final translating = messageId.isNotEmpty && (_messageTranslating[messageId] == true);
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMessageText(msg.text, msg.isMe, isDark),
          if (translating) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: msg.isMe ? Colors.black38 : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280)),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  AppLanguageService.instance.t('translating'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: msg.isMe ? Colors.black54 : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280)),
                  ),
                ),
              ],
            ),
          ],
          if (translated != null && translated.isNotEmpty && !translating) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: msg.isMe ? Colors.black12 : (isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE5E7EB)),
                    width: 1,
                  ),
                ),
              ),
              child: Text(
                translated,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.4,
                  color: msg.isMe ? Colors.black87 : (isDark ? const Color(0xFFD4D4D8) : const Color(0xFF4B5563)),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ],
      );
    }
    final showSenderName = widget.chat.isGlobal && !msg.isMe && (msg.senderName != null && msg.senderName!.isNotEmpty);
    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSenderName) ...[
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                msg.senderName!,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BondhuTokens.primary,
                ),
              ),
            ),
          ],
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * (isWide ? 0.65 : 0.82),
            ),
            padding: EdgeInsets.fromLTRB(
              type == 'image' ? 4 : 16,
              type == 'image' ? 4 : 12,
              16,
              type == 'image' ? 4 : 12,
            ),
            decoration: BoxDecoration(
              color: msg.isMe
                  ? null
                  : (isDark ? const Color(0xFF111827) : const Color(0xFFFFFFFF)),
              gradient: msg.isMe
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? const [
                              Color(0xFF22D3EE),
                              BondhuTokens.primary,
                              Color(0xFF34D399),
                            ]
                          : const [
                              Color(0xFF2DD4BF),
                              Color(0xFF14B8A6),
                              Color(0xFF10B981),
                            ],
                    )
                  : null,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(radius),
                topRight: Radius.circular(radius),
                bottomLeft: Radius.circular(msg.isMe ? radius : tailRadius),
                bottomRight: Radius.circular(msg.isMe ? tailRadius : radius),
              ),
              border: msg.isMe
                  ? null
                  : Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFE5E7EB),
                    ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
            if (PinnedMessageService.instance.isPinned(_chatId, msg.id))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.push_pin_rounded, size: 12, color: msg.isMe ? Colors.black54 : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280))),
                    const SizedBox(width: 4),
                    Text('Pinned', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: msg.isMe ? Colors.black54 : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280)))),
                  ],
                ),
              ),
            if (msg.replyToText != null && msg.replyToText!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: msg.isMe ? Colors.black38 : (isDark ? Colors.white38 : Colors.black26),
                      width: 3,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppLanguageService.instance.t('reply_to'),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: msg.isMe ? Colors.black54 : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        msg.replyToText!.length > 60 ? '${msg.replyToText!.substring(0, 60)}…' : msg.replyToText!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: msg.isMe ? Colors.black87 : (isDark ? const Color(0xFFE4E4E7) : const Color(0xFF374151)),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            content,
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: msg.isMe &&
                      (msg.localStatus == LocalMessageStatus.queued ||
                          msg.localStatus == LocalMessageStatus.failed)
                  ? () {
                      widget.chatService?.retrySendMessage(_chatId, msg.id);
                    }
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (msg.noRush == true) ...[
                    Icon(Icons.schedule_rounded, size: 12, color: msg.isMe ? Colors.black54 : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280))),
                    const SizedBox(width: 4),
                    Text(
                      'No rush',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: msg.isMe ? Colors.black54 : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280)),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (msg.localStatus == LocalMessageStatus.queued) ...[
                    Icon(Icons.schedule_outlined, size: 12, color: msg.isMe ? Colors.black54 : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280))),
                    const SizedBox(width: 4),
                    Text(
                      'Queued',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: msg.isMe ? Colors.black54 : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280)),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (msg.localStatus == LocalMessageStatus.failed) ...[
                    Icon(Icons.error_outline_rounded, size: 12, color: const Color(0xFFDC2626)),
                    const SizedBox(width: 4),
                    Text(
                      'Tap to retry',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (msg.reaction != null && msg.reaction!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                        ),
                      ),
                      child: Text(msg.reaction!, style: const TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    msg.time,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: msg.isMe ? Colors.black.withValues(alpha: 0.6) : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280)),
                    ),
                  ),
                  if (msg.isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.done_all_rounded,
                      size: 12,
                      color: msg.readAt != null ? BondhuTokens.primary : Colors.black.withValues(alpha: 0.5),
                    ),
                  ],
                ],
              ),
            ),
            if (msg.isMe && msg.readAt != null && msg.readAt!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '${AppLanguageService.instance.t('seen_at')} ${msg.readAt}',
                style: TextStyle(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ),
            ],
            if (msg.editedAt != null) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: msg.originalText != null && msg.originalText!.isNotEmpty
                    ? () => _showOriginalMessage(context, msg, isDark)
                    : null,
                child: Text(
                  '${AppLanguageService.instance.t('edited')}${msg.editedAt != null ? ' · ${msg.editedAt}' : ''}',
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: msg.isMe ? Colors.black.withValues(alpha: 0.5) : (isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280)),
                  ),
                ),
              ),
            ],
          ],
        ),
        ),
      ],
      ),
    );
  }

  void _showOriginalMessage(BuildContext context, ChatMessage msg, bool isDark) {
    final surface = isDark ? const Color(0xFF18181B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: Text(
          AppLanguageService.instance.t('original_message'),
          style: TextStyle(color: textColor, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Text(msg.originalText ?? msg.text, style: TextStyle(color: textColor)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLanguageService.instance.t('close')),
          ),
        ],
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl, bool isDark) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator(color: Colors.white70));
                  },
                  errorBuilder: (_, e, stackTrace) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image, size: 64, color: Colors.white54),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () {
                            final uri = Uri.tryParse(imageUrl);
                            if (uri != null) {
                              launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                            Navigator.of(ctx).pop();
                          },
                          icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 20),
                          label: const Text('Open in browser', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white12,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 8,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  shape: const CircleBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final RegExp _urlRegex = RegExp(
    r'https?://[^\s]+',
    caseSensitive: false,
  );

  Widget _buildMessageText(String text, bool isMe, bool isDark) {
    final color = isMe ? Colors.black : (isDark ? const Color(0xFFE4E4E7) : const Color(0xFF18181B));
    final matches = _urlRegex.allMatches(text);
    if (matches.isEmpty) {
      return Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 14,
          height: 1.5,
          color: color,
          fontWeight: isMe ? FontWeight.w500 : FontWeight.w400,
        ),
      );
    }
    final spans = <TextSpan>[];
    int lastEnd = 0;
    for (final m in matches) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, m.start),
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.5,
            color: color,
            fontWeight: isMe ? FontWeight.w500 : FontWeight.w400,
          ),
        ));
      }
      final url = m.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: GoogleFonts.inter(
          fontSize: 14,
          height: 1.5,
          color: isMe ? Colors.blue.shade900 : BondhuTokens.primary,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () async {
            final uri = Uri.tryParse(url);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
      ));
      lastEnd = m.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: GoogleFonts.inter(
          fontSize: 14,
          height: 1.5,
          color: color,
          fontWeight: isMe ? FontWeight.w500 : FontWeight.w400,
        ),
      ));
    }
    return RichText(
      text: TextSpan(children: spans),
    );
  }

  static const List<String> _emojiList = [
    '😀', '😃', '😄', '😁', '😅', '😂', '🤣', '😊', '😇', '🙂',
    '😉', '😌', '😍', '🥰', '😘', '😗', '😙', '😚', '😋', '😛',
    '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔', '🤐', '🤨',
    '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '🤥', '😌', '😔',
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💕',
  ];

  Widget _buildEmojiPicker(BuildContext context, bool isDark) {
    final bg = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFFAFAFA);
    return Container(
      height: 260,
      margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _showEmojiPicker = false),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.close_rounded, size: 20, color: isDark ? Colors.white70 : const Color(0xFF6B7280)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                childAspectRatio: 1,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: _emojiList.length,
              itemBuilder: (context, i) {
                final emoji = _emojiList[i];
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      final sel = _messageController.selection;
                      final text = _messageController.text;
                      final start = sel.start.clamp(0, text.length);
                      final end = sel.end.clamp(0, text.length);
                      _messageController.text = text.substring(0, start) + emoji + text.substring(end);
                      _messageController.selection = TextSelection.collapsed(offset: start + emoji.length);
                      setState(() {});
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndSendImage() async {
    try {
      final picker = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (picker == null || !mounted) return;
      String? url;
      // Prefer bytes so it works on web and when path is null (e.g. Android scoped storage).
      final bytes = await picker.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLanguageService.instance.t('could_not_read_image')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      final ext = picker.name.split('.').last;
      final filename = 'image_${DateTime.now().millisecondsSinceEpoch}.${ext.isEmpty ? 'jpg' : ext}';
      url = await uploadFileFromBytes(bytes, filename);
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLanguageService.instance.t('upload_failed_try_again')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      widget.chatService?.sendMessage(
        _chatId,
        url,
        'image',
        author: widget.currentUserName ?? widget.userName,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageService.instance.t('failed_send_image')), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false);
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.single;
      final name = file.name;
      String? url;
      if (kIsWeb && file.bytes != null) {
        url = await uploadFileFromBytes(file.bytes!, name);
      } else if (file.path != null) {
        url = await uploadFile(file.path!, filename: name);
      }
      if (!mounted || url == null || url.isEmpty) return;
      widget.chatService?.sendMessage(
        _chatId,
        '$url ($name)',
        'file',
        author: widget.currentUserName ?? widget.userName,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageService.instance.t('failed_send_file')), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showAddDrawer(BuildContext context, bool isDark) {
    setState(() => _addDrawerOpen = true);
    final textColor = isDark ? const Color(0xFFE4E4E7) : const Color(0xFF374151);

    final options = [
      (Icons.photo_camera_rounded, 'Photo', const Color(0xFF3B82F6), _pickAndSendImage),
      (Icons.schedule_send_rounded, AppLanguageService.instance.t('schedule_message'), const Color(0xFF8B5CF6), () { _showScheduleMessageSheet(context, isDark); }),
      (Icons.schedule_rounded, 'Reminders', BondhuTokens.primary, () { _showReplyLaterList(context, isDark); }),
      (Icons.account_balance_wallet_rounded, 'Money', const Color(0xFFF59E0B), () {}),
      (Icons.location_on_rounded, 'Location', const Color(0xFF10B981), () {}),
      (Icons.insert_drive_file_rounded, 'File', const Color(0xFF8B5CF6), _pickAndSendFile),
      (Icons.note_rounded, 'Chat note', const Color(0xFF10B981), () { _showChatNoteSheet(context, isDark); }),
    ];

    // Use modal bottom sheet for reliable behavior on web (avoids PageRouteBuilder transition issues)
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    final screenWidth = MediaQuery.sizeOf(context).width;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Navigator.of(ctx).pop();
                if (mounted) setState(() => _addDrawerOpen = false);
              },
              child: Container(color: Colors.black54),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: isWide ? 24 : 12,
                right: isWide ? 24 : 12,
                bottom: 8,
              ),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(maxWidth: isWide ? 400 : screenWidth),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha:0.1) : const Color(0xFFE5E7EB),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha:isDark ? 0.35 : 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: List.generate(options.length, (i) {
                      final e = options[i];
                      return Padding(
                        key: ValueKey('add_option_$i'),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              e.$4();
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: e.$3.withValues(alpha:0.15),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: e.$3.withValues(alpha:0.4), width: 1.5),
                                    ),
                                    child: Icon(e.$1, size: 22, color: e.$3),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    e.$2.toUpperCase(),
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: textColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ).then((_) {
      if (mounted) setState(() => _addDrawerOpen = false);
    });
  }

  void _onCallTap(BuildContext context, bool isDark, {required bool isVideo}) {
    if (widget.chat.isGlobal) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('calls_private_only')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // Require socket connection for calling (CallService will also check; this gives immediate feedback)
    if (widget.chatService != null && !widget.chatService!.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('call_not_ready')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    widget.callService?.initiateCall(widget.chat, isVideo ? 'video' : 'audio');
  }

  Future<void> _startVoiceToText(BuildContext context, bool isDark) async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    final localeId = AppLanguageService.instance.speechLocaleId;
    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        setState(() => _isListening = status == 'listening');
      },
      onError: (error) {
        if (mounted && error.errorMsg.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.errorMsg), behavior: SnackBarBehavior.floating),
          );
        }
      },
    );
    if (!mounted) return;
    if (!available) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('speech_not_available')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _voiceToTextPrefix = _messageController.text;
    setState(() => _isListening = true);
    await _speech.listen(
      localeId: localeId,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(partialResults: true),
      onResult: (result) {
        if (!mounted) return;
        final words = result.recognizedWords.trim();
        // On final result, commit this segment to prefix so the next phrase doesn't overwrite it.
        if (result.finalResult && words.isNotEmpty) {
          _voiceToTextPrefix = _voiceToTextPrefix.isEmpty ? words : '$_voiceToTextPrefix $words';
          _messageController.text = _voiceToTextPrefix;
        } else {
          // Partial or non-final: show prefix + current words (replace, don't append) to avoid "hello hello hello"
          final newText = _voiceToTextPrefix.isEmpty && words.isEmpty
              ? ''
              : _voiceToTextPrefix.isEmpty
                  ? words
                  : words.isEmpty
                      ? _voiceToTextPrefix
                      : '$_voiceToTextPrefix $words';
          _messageController.text = newText;
        }
        _messageController.selection = TextSelection.collapsed(offset: _messageController.text.length);
        final hasText = _messageController.text.trim().isNotEmpty;
        if (hasText != _hasText) setState(() => _hasText = hasText);
      },
    );
  }

  Future<void> _stopVoiceToText() async {
    if (!_isListening) return;
    await _speech.stop();
    if (mounted) setState(() => _isListening = false);
  }

  Future<void> _transcribeVoiceMessage(BuildContext context, bool isDark, ChatMessage msg) async {
    final raw = msg.text.trim();
    final audioUrl = raw.isEmpty ? '' : (raw.startsWith('http') ? raw : storageFileViewUrl(raw));
    if (audioUrl.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLanguageService.instance.t('voice_transcription_no_audio')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final hasKey = await VoiceTranscriptionService.instance.isAvailable();
    if (!hasKey && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('voice_transcription_api_key_required')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Text(AppLanguageService.instance.t('voice_transcription_loading')),
          ],
        ),
      ),
    );
    final langCode = AppLanguageService.instance.speechLocaleId == 'bn_BD' ? 'bn-BD' : 'en-US';
    final text = await VoiceTranscriptionService.instance.transcribeFromUrl(audioUrl, languageCode: langCode);
    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loading dialog
    if (text != null && text.isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) {
          final surface = isDark ? const Color(0xFF18181B) : Colors.white;
          return AlertDialog(
            backgroundColor: surface,
            title: Text(
              AppLanguageService.instance.t('transcribe_voice_to_text'),
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            content: SingleChildScrollView(
              child: SelectableText(
                text,
                style: GoogleFonts.inter(fontSize: 15, color: isDark ? Colors.white : const Color(0xFF18181B)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLanguageService.instance.t('close')),
              ),
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLanguageService.instance.t('copied')),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: Text(AppLanguageService.instance.t('copy_text')),
              ),
            ],
          );
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('voice_transcription_failed')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _onVoiceMessageLongPressStart(BuildContext context, bool isDark) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLanguageService.instance.t('voice_msg_not_web')), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (_isRecordingVoiceMessage) return;
    final recorder = AudioRecorder();
    final hasPermission = await recorder.hasPermission();
    if (!context.mounted) return;
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLanguageService.instance.t('mic_permission_required')), behavior: SnackBarBehavior.floating),
      );
      recorder.dispose();
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/bondhu_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100), path: path);
      if (!context.mounted) return;
      _voiceRecorder = recorder;
      _voiceRecordPath = path;
      _voiceRecordSeconds = 0;
      _voiceRecordTimer?.cancel();
      _voiceRecordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _voiceRecordSeconds++);
      });
      setState(() => _isRecordingVoiceMessage = true);
    } catch (e) {
      recorder.dispose();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageService.instance.t('voice_recording_failed')), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _onVoiceMessageLongPressEnd() async {
    if (!_isRecordingVoiceMessage || _voiceRecorder == null) return;
    _voiceRecordTimer?.cancel();
    _voiceRecordTimer = null;
    final recorder = _voiceRecorder!;
    final path = _voiceRecordPath;
    _voiceRecorder = null;
    _voiceRecordPath = null;
    setState(() => _isRecordingVoiceMessage = false);
    try {
      final stoppedPath = await recorder.stop();
      recorder.dispose();
      if (mounted && (stoppedPath != null || path != null)) _sendVoiceMessage(stoppedPath ?? path!);
    } catch (_) {
      recorder.dispose();
    }
  }

  Future<void> _sendVoiceMessage(String path) async {
    final svc = widget.chatService;
    if (svc == null) return;
    try {
      final url = await uploadFile(path, filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
      if (!mounted || url == null || url.isEmpty) return;
      svc.sendMessage(
        _chatId,
        url,
        'audio',
        author: widget.currentUserName ?? widget.userName,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageService.instance.t('failed_send_voice')), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Widget _buildInputBar(BuildContext context, bool isDark) {
    // Original design: full-width bar with top border, boxed input area, green send/mic button
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    const barHeightMobile = 40.0;
    const barHeightWide = 48.0;
    final barHeight = isWide ? barHeightWide : barHeightMobile;
    final buttonSize = barHeight;
    final gap = isWide ? 12.0 : 8.0;
    final addBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F5F9);
    final addBorder = isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFE2E8F0);
    final inputBg = isDark ? const Color(0xFF0E0E10) : const Color(0xFFF8FAFC);
    final iconGrey = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF475569);
    final hintGrey = isDark ? const Color(0xFF71717A) : const Color(0xFF64748B);
    final padH = isWide ? 20.0 : 12.0;
    const inputRadius = 20.0;
    const padTop = 6.0;
    const padBottom = 19.0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.9) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(left: padH, right: padH, top: padTop, bottom: padBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isRecordingVoiceMessage) _buildVoiceRecordingOverlay(context, isDark),
          if (_replyToMessage != null) _buildReplyPreview(context, isDark),
          if (_isListening) _buildVoiceToTextBar(context, isDark),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_addDrawerOpen) {
                    Navigator.of(context).pop();
                  } else {
                    _showAddDrawer(context, isDark);
                  }
                },
                child: Container(
                  key: _addButtonKey,
                  width: buttonSize,
                  height: buttonSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: addBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: addBorder, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    _addDrawerOpen ? Icons.close_rounded : Icons.add_rounded,
                    size: isWide ? 22 : 20,
                    color: iconGrey,
                  ),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(inputRadius),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFD1D5DB),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(inputRadius),
                    child: Row(
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() => _showEmojiPicker = !_showEmojiPicker),
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(Icons.emoji_emotions_outlined, size: 22, color: iconGrey),
                            ),
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _startVoiceToText(context, isDark),
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.mic_rounded,
                                size: 20,
                                color: _isListening ? BondhuTokens.primary : iconGrey,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            onChanged: (v) {
                              final hasText = v.trim().isNotEmpty;
                              if (hasText != _hasText && mounted) {
                                _hasText = hasText;
                                setState(() {});
                              }
                              widget.chatService?.emitTyping(_chatId, hasText);
                              _draftDebounceTimer?.cancel();
                              _draftDebounceTimer = Timer(const Duration(milliseconds: 800), () {
                                if (!mounted) return;
                                DraftService.instance.setDraft(_chatId, _messageController.text);
                              });
                            },
                            decoration: InputDecoration(
                              hintText: AppLanguageService.instance.t('type_message'),
                              hintStyle: TextStyle(color: hintGrey, fontSize: isWide ? 15 : 14),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: (barHeight - 20) / 2),
                              isDense: true,
                              isCollapsed: true,
                            ),
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF18181B),
                              fontSize: isWide ? 15 : 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: gap),
              GestureDetector(
                onLongPressStart: _messageController.text.trim().isEmpty
                    ? (_) => _onVoiceMessageLongPressStart(context, isDark)
                    : null,
                onLongPressEnd: _messageController.text.trim().isEmpty ? (_) => _onVoiceMessageLongPressEnd() : null,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (_messageController.text.trim().isNotEmpty) {
                        _sendText();
                      }
                    },
                    borderRadius: BorderRadius.circular(buttonSize / 2),
                    child: Container(
                      key: _voiceButtonKey,
                      width: buttonSize,
                      height: buttonSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _isRecordingVoiceMessage
                            ? Colors.red.shade400
                            : const Color(0xFF14B8A6),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                        color: (_isRecordingVoiceMessage ? Colors.red : const Color(0xFF14B8A6)).withValues(alpha: 0.22),
                            blurRadius: 8,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Icon(
                        _messageController.text.trim().isEmpty ? Icons.mic_rounded : Icons.send_rounded,
                        size: isWide ? 22 : 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildVoiceRecordingOverlay(BuildContext context, bool isDark) {
    final surface = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final subColor = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: BondhuTokens.primary, width: 3)),
      ),
      child: Row(
        children: [
          Icon(Icons.mic_rounded, size: 20, color: BondhuTokens.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLanguageService.instance.t('voice_message_recording'),
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF18181B)),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLanguageService.instance.t('voice_message_release'),
                  style: GoogleFonts.inter(fontSize: 11, color: subColor),
                ),
              ],
            ),
          ),
          Text(
            _formatDuration(_voiceRecordSeconds),
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: BondhuTokens.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceToTextBar(BuildContext context, bool isDark) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF111113);
    final textMuted = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? BondhuTokens.primary.withValues(alpha: 0.12) : BondhuTokens.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BondhuTokens.primary.withValues(alpha: 0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: BondhuTokens.primary.withValues(alpha: isDark ? 0.08 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: BondhuTokens.primary.withValues(alpha: isDark ? 0.2 : 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.mic_rounded, size: 20, color: BondhuTokens.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLanguageService.instance.t('voice_to_text_listening'),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap Done when you\'re finished speaking',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500, color: textMuted),
                ),
              ],
            ),
          ),
          Material(
            color: BondhuTokens.primary,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _stopVoiceToText,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Text(
                  AppLanguageService.instance.t('done'),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(BuildContext context, bool isDark) {
    final reply = _replyToMessage;
    if (reply == null) return const SizedBox.shrink();
    final subColor = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280);
    final textColor = isDark ? Colors.white : const Color(0xFF18181B);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF27272A) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: BondhuTokens.primary, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLanguageService.instance.t('reply_to'),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: BondhuTokens.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reply.text.length > 80 ? '${reply.text.substring(0, 80)}…' : reply.text,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: textColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => setState(() => _replyToMessage = null),
            style: IconButton.styleFrom(
              foregroundColor: subColor,
              padding: const EdgeInsets.all(4),
              minimumSize: const Size(32, 32),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen media gallery: photos grid, voice messages and files lists.
class _MediaGalleryScreen extends StatelessWidget {
  const _MediaGalleryScreen({
    required this.isDark,
    required this.images,
    required this.voiceMessages,
    required this.files,
    this.chatName,
    this.onPlayVoiceMessage,
  });

  final bool isDark;
  final List<ChatMessage> images;
  final List<ChatMessage> voiceMessages;
  final List<ChatMessage> files;
  final String? chatName;
  /// When user taps play on a voice message, call with (messageId, audioUrl) then pop so chat shows and plays.
  final void Function(String messageId, String audioUrl)? onPlayVoiceMessage;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF0A0A0B) : const Color(0xFFF8F9FA);
    final cardBg = isDark ? const Color(0xFF161618) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111113);
    final textMuted = isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFEEF0F2);

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: textPrimary),
          tooltip: 'Back',
        ),
        title: Text(
          'Media & files',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (images.isNotEmpty) ...[
              _sectionLabel('Photos', textPrimary),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  const crossAxisCount = 3;
                  const spacing = 8.0;
                  final w = constraints.maxWidth;
                  final size = w > 0 ? (w - (crossAxisCount - 1) * spacing) / crossAxisCount : 100.0;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: images.map((m) {
                      final raw = m.text.trim();
                      final url = raw.isEmpty ? '' : (raw.startsWith('http') ? raw : storageFileViewUrl(raw));
                      final isUrl = url.startsWith('http://') || url.startsWith('https://');
                      return SizedBox(
                        width: size,
                        height: size,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: isUrl
                              ? Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, Object error, StackTrace? stackTrace) => _mediaPlaceholder(Icons.image_rounded, cardBg, borderColor, size),
                                )
                              : _mediaPlaceholder(Icons.image_rounded, cardBg, borderColor, size),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 28),
            ],
            if (voiceMessages.isNotEmpty) ...[
              _sectionLabel('Voice messages', textPrimary),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  children: voiceMessages.asMap().entries.map((e) {
                    final m = e.value;
                    final isLast = e.key == voiceMessages.length - 1;
                    final audioUrl = m.text.trim().isEmpty
                        ? ''
                        : (m.text.startsWith('http') ? m.text : storageFileViewUrl(m.text));
                    final canPlay = audioUrl.isNotEmpty && onPlayVoiceMessage != null;
                    return Column(
                      key: ValueKey('voice_${m.id}'),
                      children: [
                        ListTile(
                          key: ValueKey('voice_tile_${m.id}'),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: BondhuTokens.primary.withValues(alpha: isDark ? 0.2 : 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.mic_rounded, color: BondhuTokens.primary, size: 22),
                          ),
                          title: Text(
                            'Voice message',
                            style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary),
                          ),
                          subtitle: Text(
                            m.time,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted),
                          ),
                          trailing: canPlay
                              ? IconButton(
                                  onPressed: () => onPlayVoiceMessage!(m.id, audioUrl),
                                  icon: Icon(Icons.play_circle_filled_rounded, color: BondhuTokens.primary, size: 36),
                                  tooltip: 'Play',
                                )
                              : null,
                        ),
                        if (!isLast) Divider(height: 1, indent: 76, endIndent: 16, color: borderColor),
                      ],
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 28),
            ],
            if (files.isNotEmpty) ...[
              _sectionLabel('Files', textPrimary),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  children: files.asMap().entries.map((e) {
                    final m = e.value;
                    final isLast = e.key == files.length - 1;
                    return Column(
                      key: ValueKey('file_${m.id}'),
                      children: [
                        ListTile(
                          key: ValueKey('file_tile_${m.id}'),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: BondhuTokens.primary.withValues(alpha: isDark ? 0.2 : 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.insert_drive_file_rounded, color: BondhuTokens.primary, size: 22),
                          ),
                          title: Text(
                            m.text.length > 50 ? '${m.text.substring(0, 50)}…' : m.text,
                            style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            m.time,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted),
                          ),
                        ),
                        if (!isLast) Divider(height: 1, indent: 76, endIndent: 16, color: borderColor),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  Widget _mediaPlaceholder(IconData icon, Color bg, Color border, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 32, color: border),
    );
  }
}

/// One item in the chat list: either a date separator or a message.
class _ChatListItem {
  _ChatListItem({this.dateLabel, this.message});
  final String? dateLabel;
  final ChatMessage? message;
  bool get isDateSeparator => dateLabel != null;
}

/// Avatar that loads from URL with error handling to avoid ImageCodecException.
class _SafeAvatar extends StatelessWidget {
  const _SafeAvatar({this.url, required this.size, required this.isDark});

  final String? url;
  final double size;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E5E5);
    final iconColor = isDark ? const Color(0xFF737373) : const Color(0xFF737373);
    if (url?.isEmpty ?? true) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(Icons.person_rounded, color: iconColor, size: size * 0.5),
      );
    }
    final cacheSize = (size * 1.5).round().clamp(48, 256);
    return ClipOval(
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        errorBuilder: (_, error, stackTrace) => Container(
          width: size,
          height: size,
          color: bg,
          child: Icon(Icons.person_rounded, color: iconColor, size: size * 0.5),
        ),
      ),
    );
  }
}

/// Paints the website chat-area-pattern (style.css).
/// Black + green dots: 24px grid, 12px offset. Light: black 0.14, green 0.12. Dark: white 0.30, green 0.22.
class _ChatAreaPatternPainter extends CustomPainter {
  _ChatAreaPatternPainter({required this.isDark});

  final bool isDark;

  static const double _cell = 24.0;
  static const double _offset = 12.0;
  static const double _dotRadius = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Optimized: Pre-calculate paint objects and reduce iterations
    final dot1Paint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.30)
          : Colors.black.withValues(alpha: 0.06);
    final dot2Paint = Paint()
      ..color = isDark
          ? const Color(0xFF00C896).withValues(alpha: 0.22)
          : const Color(0xFF14B8A6).withValues(alpha: 0.07);
    
    // Calculate bounds once
    final maxX = size.width + _cell;
    final maxY = size.height + _cell;
    
    // Draw both layers in single pass for better performance
    for (var y = 0.0; y < maxY; y += _cell) {
      for (var x = 0.0; x < maxX; x += _cell) {
        canvas.drawCircle(Offset(x, y), _dotRadius, dot1Paint);
        canvas.drawCircle(Offset(x + _offset, y + _offset), _dotRadius, dot2Paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChatAreaPatternPainter oldDelegate) => 
      oldDelegate.isDark != isDark;
}
