import 'dart:async';
// ignore_for_file: unused_field - _ChatViewDims constants reserved for layout parity
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../app_animations.dart';
import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/supabase_service.dart';
import '../services/block_service.dart';
import '../services/chat_service.dart';
import '../services/nickname_service.dart';
import '../services/mood_status_service.dart';
import '../services/call_service.dart';
import '../services/notification_service.dart';
import 'contact_page.dart';
import 'chat_screen.dart';
import 'new_group_screen.dart';
import 'notification_panel.dart';
import 'hidden_chats_screen.dart';
import 'story_overlay.dart';
import '../services/hidden_chats_service.dart';
import '../widgets/bondhu_app_logo.dart';

export '../services/chat_service.dart' show ChatItem, ChatMessage;

// ---------- Dimensions from ChatView.vue (Tailwind: 1 = 4px) ----------
// ignore: unused_element
abstract class _ChatViewDims {
  static const double pl5 = 20;          // pl-5, pr-5, ml-5, mr-5
  static const double pr12Md = 48;      // md:pr-12, md:mr-12
  static const double pt6 = 24;         // pt-6
  static const double pb2 = 8;          // pb-2
  static const double h14 = 56;         // h-14
  static const double mb6 = 24;         // mb-6
  static const double w10 = 40;         // w-10 h-10 (header buttons)
  static const double mx4 = 16;         // mx-4
  static const double helloFont = 10;   // text-[10px]
  static const double nameFont = 20;    // text-xl
  static const double nameWidth = 160;  // w-40
  static const double mb05 = 2;         // mb-0.5, mt-0.5
  static const double gap5 = 20;        // gap-5 (stories row)
  static const double mb4 = 16;         // mb-4
  static const double storySize = 60;   // w-[60px] h-[60px]
  static const double gap2Story = 8;    // gap-2 (between circle and label)
  static const double labelFont = 11;   // text-[11px]
  static const double labelWidth = 64;  // w-16
  static const double cardRadius = 32;  // rounded-[32px]
  static const double px4 = 16;         // px-4
  static const double py5 = 20;         // py-5
  static const double chipGap = 8;      // gap-2
  static const double chipPx = 16;      // px-4
  static const double chipPy = 10;      // py-2.5
  static const double chipRadius = 12;  // rounded-xl
  static const double chipFont = 11;    // text-[11px]
  static const double chipIconMr = 4;   // mr-1
  static const double chipIconSize = 12;
  static const double listSpaceY = 4;   // space-y-1
  static const double listP = 12;       // p-3
  static const double listRadius = 20; // rounded-[20px]
  static const double avatarSize = 44; // w-[44px] h-[44px]
  static const double ml35 = 14;        // ml-3.5
  static const double nameFontList = 14;   // text-[14px]
  static const double timeFont = 10;    // text-[10px]
  static const double msgFont = 12;     // text-[12px]
  static const double unreadSize = 12;  // w-3 h-3
  static const double unreadBorder = 2; // border-2
  static const double fabSize = 56;    // w-[56px] h-[56px]
  static const double bottom8 = 32;     // bottom-8, right-8
  static const double right12Md = 48;   // md:right-12
  static const double fabIconSize = 20; // text-xl
  static const double cardMaxWidth = 412; // 480 - 20 - 48
  static const double listMinHeight = 100; // min-h-[100px]
}

class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.currentUser,
    required this.chatService,
    required this.callService,
    this.userName,
    this.userAvatarUrl,
    required this.isDark,
    this.pushOpenChatId,
    this.onOpenGlobalSearch,
    this.chatInitFailed = false,
    this.onRetryChatInit,
    this.onOpenNotifications,
  });

  final AuthUser currentUser;
  final ChatService chatService;
  final CallService callService;
  final String? userName;
  final String? userAvatarUrl;
  final bool isDark;
  final ValueNotifier<String?>? pushOpenChatId;
  /// When set, tapping the search icon opens global search (people + chats) instead of local chat filter.
  final VoidCallback? onOpenGlobalSearch;
  /// When true, show a banner that connection failed with retry.
  final bool chatInitFailed;
  final VoidCallback? onRetryChatInit;
  /// Open the dedicated notifications screen.
  final VoidCallback? onOpenNotifications;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  bool _showLocalSearch = false;
  String _searchQuery = '';
  String? _selectedChatId;
  List<ChatItem> _chats = [];
  List<StoryItem> _stories = [];
  bool _storiesLoading = true;
  bool _addingStory = false;
  StreamSubscription<List<ChatItem>>? _chatsSub;
  Timer? _chatsDebounceTimer;
  VoidCallback? _pushOpenChatIdListener;
  VoidCallback? _blockListListener;
  VoidCallback? _hiddenChatsListener;

  static List<ChatItem> _filterBlocked(List<ChatItem> list) {
    return list.where((c) => !BlockService.instance.isBlocked(c.id)).toList();
  }

  static List<ChatItem> _sortChats(List<ChatItem> list) {
    list.sort((a, b) {
      final aPin = a.pinned == true;
      final bPin = b.pinned == true;
      if (aPin != bPin) return aPin ? -1 : 1;
      return 0;
    });
    return list;
  }

  @override
  void initState() {
    super.initState();
    NicknameService.instance.load();
    HiddenChatsService.instance.setAccountScope(widget.currentUser.email).then((_) {
      HiddenChatsService.instance.load();
    });
    _hiddenChatsListener = () { if (mounted) setState(() {}); };
    HiddenChatsService.instance.hiddenIds.addListener(_hiddenChatsListener!);
    _chats = _sortChats(_filterBlocked(List.from(widget.chatService.chats)));
    _blockListListener = () {
      if (!mounted) return;
      setState(() => _chats = _sortChats(_filterBlocked(List.from(widget.chatService.chats))));
    };
    BlockService.instance.blockedIdsNotifier.addListener(_blockListListener!);
    // Debounce chat list updates by one frame so taps aren't lost during rapid updates.
    _chatsSub = widget.chatService.chatsStream.listen(
      (list) {
        if (!mounted) return;
        _chatsDebounceTimer?.cancel();
        _chatsDebounceTimer = Timer(const Duration(milliseconds: 16), () {
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _chats = _sortChats(_filterBlocked(List.from(list))));
          });
        });
      },
      onError: (e, st) {
        if (kDebugMode) debugPrint('[ChatView] chatsStream error: $e\n$st');
      },
      cancelOnError: false,
    );
    final notifier = widget.pushOpenChatId;
    if (notifier != null) {
      void onPushOpenChatId() {
        final raw = notifier.value;
        if (raw == null || !mounted) return;
        notifier.value = null;
        final (id, name) = _parseOpenChatIdAndName(raw);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ChatItem? chat;
          for (final c in widget.chatService.chats) {
            if (c.id.toLowerCase() == id.toLowerCase()) {
              chat = c;
              break;
            }
          }
          if (chat != null) {
            if (!name.contains('@') && name != id) {
              widget.chatService.updateChatName(id, name);
              _openChat(chat.copyWith(name: name));
            } else {
              _openChat(chat);
            }
          } else {
            final fallback = ChatService.createChatObject(id, name);
            widget.chatService.addChat(fallback);
            final myEmail = widget.currentUser.email?.trim().toLowerCase();
            if (myEmail != null && id.contains('@') && id != myEmail) {
              addContactToProfile(myEmail, id);
            }
            _openChat(fallback);
          }
        });
      }
      _pushOpenChatIdListener = onPushOpenChatId;
      notifier.addListener(onPushOpenChatId);
      // Handle cold start: if app was opened from notification tap, value may already be set before listener was added.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final raw = notifier.value;
        if (raw == null || raw.isEmpty) return;
        notifier.value = null;
        final (id, name) = _parseOpenChatIdAndName(raw);
        ChatItem? chat;
        for (final c in widget.chatService.chats) {
          if (c.id.toLowerCase() == id.toLowerCase()) {
            chat = c;
            break;
          }
        }
        if (chat != null) {
          if (!name.contains('@') && name != id) {
            widget.chatService.updateChatName(id, name);
            _openChat(chat.copyWith(name: name));
          } else {
            _openChat(chat);
          }
        } else {
          final fallback = ChatService.createChatObject(id, name);
          widget.chatService.addChat(fallback);
          final myEmail = widget.currentUser.email?.trim().toLowerCase();
          if (myEmail != null && id.contains('@') && id != myEmail) {
            addContactToProfile(myEmail, id);
          }
          _openChat(fallback);
        }
      });
    }
    _loadStories();
    // Defer addChat so stream doesn't emit during initState (avoids crash after login).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_chats.any((c) => c.id == 'group_global')) {
        widget.chatService.addChat(ChatService.createChatObject('group_global', AppLanguageService.instance.t('global_chat')));
      }
    });
  }

  Future<void> _loadStories() async {
    if (!mounted) return;
    setState(() => _storiesLoading = true);
    try {
      final docs = await getStories();
      if (!mounted) return;
      final items = storyDocumentsToItems(docs, widget.currentUser.email);
      setState(() {
        _stories = items.where((s) => s.mediaUrl.isNotEmpty).toList();
        _storiesLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _storiesLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLanguageService.instance.t('could_not_load_stories')),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: AppLanguageService.instance.t('retry'),
              onPressed: () => _loadStories(),
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    if (_pushOpenChatIdListener != null) widget.pushOpenChatId?.removeListener(_pushOpenChatIdListener!);
    _chatsDebounceTimer?.cancel();
    _chatsDebounceTimer = null;
    _chatsSub?.cancel();
    _chatsSub = null;
    if (_blockListListener != null) {
      BlockService.instance.blockedIdsNotifier.removeListener(_blockListListener!);
      _blockListListener = null;
    }
    if (_hiddenChatsListener != null) {
      HiddenChatsService.instance.hiddenIds.removeListener(_hiddenChatsListener!);
      _hiddenChatsListener = null;
    }
    super.dispose();
  }

  void _openHiddenChatsScreen(BuildContext context, bool isDark) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HiddenChatsScreen(
          chatService: widget.chatService,
          callService: widget.callService,
          currentUser: widget.currentUser,
          userName: widget.userName,
          userAvatarUrl: widget.userAvatarUrl,
          isDark: isDark,
        ),
      ),
    );
  }

  /// Parses pushOpenChatId value: "userId" or "userId|Display Name". Returns (id, displayName).
  static (String, String) _parseOpenChatIdAndName(String raw) {
    final pipe = raw.indexOf('|');
    if (pipe >= 0) {
      final id = raw.substring(0, pipe).trim();
      final name = raw.substring(pipe + 1).trim();
      return (id, name.isNotEmpty ? name : ChatService.formatName(id));
    }
    return (raw.trim(), ChatService.formatName(raw));
  }

  /// Chats visible in main list (not archived, not hidden).
  List<ChatItem> get _mainChats => _chats
      .where((c) => c.archivedAtMs == null && !HiddenChatsService.instance.isHidden(c.id))
      .toList();

  /// Archived chats (or snoozed and not yet ended). Exclude hidden so they only appear in Hidden Chats screen.
  List<ChatItem> get _archivedChats => _chats
      .where((c) => c.archivedAtMs != null && !HiddenChatsService.instance.isHidden(c.id))
      .toList();

  List<ChatItem> get _filteredChats {
    final main = _mainChats;
    if (_searchQuery.trim().isEmpty) return main;
    final q = _searchQuery.toLowerCase();
    return main.where((c) =>
        c.name.toLowerCase().contains(q) ||
        (c.email?.toLowerCase().contains(q) ?? false)).toList();
  }

  List<ChatItem> get _filteredArchivedChats {
    final archived = _archivedChats;
    if (_searchQuery.trim().isEmpty) return archived;
    final q = _searchQuery.toLowerCase();
    return archived.where((c) =>
        c.name.toLowerCase().contains(q) ||
        (c.email?.toLowerCase().contains(q) ?? false)).toList();
  }

  ChatItem? get _globalChat {
    for (final c in _chats) {
      if (c.id == 'group_global') return c;
    }
    return null;
  }

  Widget _buildChatList(bool isDark) {
    final mainList = _filteredChats;
    final archivedList = _filteredArchivedChats;
    final hasArchived = archivedList.isNotEmpty;
    final totalCount = mainList.length + (hasArchived ? 1 + archivedList.length : 0);
    if (totalCount == 0) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 200),
            child: Center(
              child: Text(
                AppLanguageService.instance.t('no_conversations'),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      cacheExtent: kIsWeb ? 300 : 500,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemCount: totalCount,
      padding: const EdgeInsets.only(right: 4),
      separatorBuilder: (_, index) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        if (index < mainList.length) {
          final chat = mainList[index];
          return RepaintBoundary(
            key: ValueKey('chat_${chat.id}'),
            child: _chatListTile(
              context,
              chat,
              isDark,
              isSelected: _selectedChatId == chat.id,
              isInArchivedSection: false,
              onArchiveSnooze: () => _showChatArchiveSnoozeModal(context, chat, isDark, isArchived: false),
            ),
          );
        }
        if (index == mainList.length) {
          return Padding(
            padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
            child: Text(
              AppLanguageService.instance.t('archived'),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
              ),
            ),
          );
        }
        final archivedIndex = index - mainList.length - 1;
        final chat = archivedList[archivedIndex];
        return RepaintBoundary(
          key: ValueKey('archived_${chat.id}'),
          child: _chatListTile(
            context,
            chat,
            isDark,
            isSelected: _selectedChatId == chat.id,
            isInArchivedSection: true,
            onArchiveSnooze: () => _showChatArchiveSnoozeModal(context, chat, isDark, isArchived: true),
          ),
        );
      },
    );
  }

  void _showChatArchiveSnoozeModal(BuildContext context, ChatItem chat, bool isDark, {required bool isArchived}) {
    _showChatQuickActions(context, chat, isDark, isArchived: isArchived);
  }

  void _showChatQuickActions(BuildContext context, ChatItem chat, bool isDark, {bool isArchived = false}) {
    final t = AppLanguageService.instance.t;
    final textPrimary = isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight;
    final surface = isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight;
    final muted = chat.muteMessages && chat.muteCalls;
    final isBlocked = BlockService.instance.isBlocked(chat.id);
    final isGlobal = chat.isGlobal;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        NicknameService.instance.getDisplayName(chat),
                        style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                      style: IconButton.styleFrom(foregroundColor: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (isArchived)
                  _quickActionTile(ctx, isDark, Icons.inbox_outlined, t('unarchive_chat'), () {
                    widget.chatService.setArchived(chat.id, false);
                    Navigator.pop(ctx);
                  })
                else ...[
                  _quickActionTile(
                    ctx,
                    isDark,
                    muted ? Icons.notifications_rounded : Icons.notifications_off_rounded,
                    t('mute'),
                    () {
                      Navigator.pop(ctx);
                      _showMuteSubSheet(context, chat, isDark);
                    },
                  ),
                  _quickActionTile(ctx, isDark, chat.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, chat.pinned ? 'Unpin' : 'Pin', () {
                    widget.chatService.setPinned(chat.id, !chat.pinned);
                    Navigator.pop(ctx);
                  }),
                  _quickActionTile(ctx, isDark, Icons.archive_outlined, t('archive_chat'), () {
                    widget.chatService.setArchived(chat.id, true);
                    Navigator.pop(ctx);
                  }),
                  _quickActionTile(ctx, isDark, Icons.schedule_rounded, 'Snooze', () {
                    Navigator.pop(ctx);
                    _showSnoozeSubSheet(context, chat, isDark);
                  }),
                  if (!isGlobal)
                    _quickActionTile(ctx, isDark, Icons.lock_rounded, t('move_to_hidden'), () async {
                      await HiddenChatsService.instance.addHidden(chat.id);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('${NicknameService.instance.getDisplayName(chat)} ${t('move_to_hidden').toLowerCase()}'),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }),
                  if (!isGlobal) ...[
                    _quickActionTile(
                      ctx,
                      isDark,
                      Icons.block_rounded,
                      isBlocked ? t('unblock') : t('block'),
                      () {
                        Navigator.pop(ctx);
                        _showBlockSubSheet(context, chat, isDark, isBlocked: isBlocked);
                      },
                    ),
                    _quickActionTile(ctx, isDark, Icons.delete_outline_rounded, 'Delete chat', () {
                      Navigator.pop(ctx);
                      _confirmDeleteChat(context, chat, isDark);
                    }, isDestructive: true),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickActionTile(BuildContext ctx, bool isDark, IconData icon, String label, VoidCallback onTap, {bool isDestructive = false}) {
    final color = isDestructive ? const Color(0xFFDC2626) : BondhuTokens.primary;
    final textColor = isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 14),
              Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w500, color: isDestructive ? color : textColor)),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnoozeSubSheet(BuildContext context, ChatItem chat, bool isDark) {
    final t = AppLanguageService.instance.t;
    final textPrimary = isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight;
    final surface = isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Snooze chat', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary)),
              const SizedBox(height: 12),
              ListTile(leading: const Icon(Icons.schedule_rounded, color: BondhuTokens.primary), title: Text(t('snooze_24h'), style: TextStyle(color: textPrimary)), onTap: () { widget.chatService.setSnooze(chat.id, const Duration(hours: 24)); Navigator.pop(ctx); }),
              ListTile(leading: const Icon(Icons.schedule_rounded, color: BondhuTokens.primary), title: Text(t('snooze_7d'), style: TextStyle(color: textPrimary)), onTap: () { widget.chatService.setSnooze(chat.id, const Duration(days: 7)); Navigator.pop(ctx); }),
              ListTile(leading: const Icon(Icons.schedule_rounded, color: BondhuTokens.primary), title: Text(t('snooze_30d'), style: TextStyle(color: textPrimary)), onTap: () { widget.chatService.setSnooze(chat.id, const Duration(days: 30)); Navigator.pop(ctx); }),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteChat(BuildContext context, ChatItem chat, bool isDark) {
    final t = AppLanguageService.instance.t;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight,
        title: Text(t('delete_chat')),
        content: Text(t('delete_chat_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () {
              widget.chatService.removeChat(chat.id);
              Navigator.pop(ctx);
            },
            child: Text(t('delete')),
          ),
        ],
      ),
    );
  }

  /// Advanced mute sheet: choose what to mute for this chat.
  void _showMuteSubSheet(BuildContext context, ChatItem chat, bool isDark) {
    final t = AppLanguageService.instance.t;
    final textPrimary = isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight;
    final surface = isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight;
    final mutedMessages = chat.muteMessages;
    final mutedCalls = chat.muteCalls;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('mute'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppLanguageService.instance.t('mute_messages'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(
                  Icons.notifications_off_rounded,
                  color: mutedMessages && mutedCalls ? BondhuTokens.primary : (isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight),
                ),
                title: Text(
                  t('mute'),
                  style: TextStyle(color: textPrimary),
                ),
                subtitle: Text(
                  AppLanguageService.instance.t('mute_messages'),
                  style: TextStyle(fontSize: 12, color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight),
                ),
                onTap: () {
                  widget.chatService.setMuteSettings(chat.id, muteMessages: true, muteCalls: true);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: mutedMessages && !mutedCalls ? BondhuTokens.primary : (isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight),
                ),
                title: Text(
                  t('mute_messages'),
                  style: TextStyle(color: textPrimary),
                ),
                onTap: () {
                  widget.chatService.setMuteSettings(chat.id, muteMessages: true, muteCalls: false);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.call_end_rounded,
                  color: !mutedMessages && mutedCalls ? BondhuTokens.primary : (isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight),
                ),
                title: Text(
                  t('mute_calls'),
                  style: TextStyle(color: textPrimary),
                ),
                onTap: () {
                  widget.chatService.setMuteSettings(chat.id, muteMessages: false, muteCalls: true);
                  Navigator.pop(ctx);
                },
              ),
              const Divider(height: 24),
              ListTile(
                leading: Icon(
                  Icons.volume_up_rounded,
                  color: (!mutedMessages && !mutedCalls) ? BondhuTokens.primary : (isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight),
                ),
                title: Text(
                  AppLanguageService.instance.t('unmute'),
                  style: TextStyle(color: textPrimary),
                ),
                onTap: () {
                  widget.chatService.setMuteSettings(chat.id, muteMessages: false, muteCalls: false);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Advanced block sheet: explain effects and confirm block/unblock.
  void _showBlockSubSheet(BuildContext context, ChatItem chat, bool isDark, {required bool isBlocked}) {
    final t = AppLanguageService.instance.t;
    final textPrimary = isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight;
    final surface = isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight;
    final destructive = const Color(0xFFDC2626);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.block_rounded, color: destructive),
                  const SizedBox(width: 8),
                  Text(
                    isBlocked ? t('unblock') : t('block'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                isBlocked
                    ? AppLanguageService.instance.t('unblock_description')
                    : AppLanguageService.instance.t('block_description'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              if (!isBlocked)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: destructive,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    await BlockService.instance.add(chat.id);
                    // Also remove local chat history for extra privacy.
                    widget.chatService.removeChat(chat.id);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(t('block')),
                )
              else
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: BondhuTokens.primary,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    await BlockService.instance.remove(chat.id);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(t('unblock')),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  AppLanguageService.instance.t('cancel'),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openChatById(String chatId) {
    final norm = chatId.trim().toLowerCase();
    for (final c in _chats) {
      if (c.id.trim().toLowerCase() == norm) {
        _openChat(c);
        return;
      }
    }
  }

  void _ensureGlobalAndOpen() {
    ChatItem? global = _globalChat;
    if (global == null) {
      global = ChatService.createChatObject('group_global', AppLanguageService.instance.t('global_chat'));
      widget.chatService.addChat(global);
      // Defer open to next frame so stream-driven setState completes first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openChat(global!);
      });
    } else {
      _openChat(global);
    }
  }

  void _showNewGroupModal(BuildContext context, bool isDark) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NewGroupScreen(
          currentUserEmail: widget.currentUser.email,
          isDark: isDark,
          chatService: widget.chatService,
          onCreateGroup: (ChatItem group) {
            if (context.mounted) _openChat(group);
          },
        ),
      ),
    );
  }

  void _openContactPage(BuildContext context, bool isDark) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ContactPage(
          currentUserEmail: widget.currentUser.email,
          currentUserName: widget.currentUser.name ?? widget.userName,
          isDark: isDark,
          chatService: widget.chatService,
          onOpenChatWithUser: (String userId) {
            if (context.mounted) Navigator.of(context).pop();
            widget.pushOpenChatId?.value = userId;
          },
        ),
      ),
    );
  }

  void _openChat(ChatItem chat) {
    widget.chatService.selectChat(chat.id); // clear unread when opening
    setState(() => _selectedChatId = chat.id);
    // Ensure private chat partner is in contacts so they show on Contacts page
    if (!chat.isGlobal && !chat.isGroup && chat.id.contains('@')) {
      final myEmail = widget.currentUser.email?.trim().toLowerCase();
      if (myEmail != null && chat.id != myEmail) {
        addContactToProfile(myEmail, chat.id);
      }
    }
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
          chat: chat,
          chatService: widget.chatService,
          callService: widget.callService,
          currentUserEmail: widget.currentUser.email,
          currentUserName: widget.currentUser.name ?? widget.userName,
          userName: widget.userName,
          userAvatarUrl: widget.userAvatarUrl,
          isDark: widget.isDark,
          onNavigateToChat: (chatId) {
            Navigator.of(context).pop();
            _openChatById(chatId);
          },
        ),
        transitionDuration: AppAnimations.normal,
        reverseTransitionDuration: AppAnimations.normal,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curve = CurvedAnimation(
            parent: animation,
            curve: AppAnimations.easeOut,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curve),
            child: FadeTransition(
              opacity: curve,
              child: child,
            ),
          );
        },
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _selectedChatId = null);
        _loadStories();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    final isDark = widget.isDark;
    return Scaffold(
      body: Container(
        decoration: isDark
            ? BoxDecoration(color: BondhuTokens.bgDark)
            : BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFE6F9F4),
                    const Color(0xFFF4FCF9),
                    Colors.white,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
        child: SafeArea(
          child: Stack(
            children: [
              Row(
                children: [
                  _buildSidebar(context, isWide, isDark),
                  if (isWide) Expanded(child: _buildEmptyState(context, isDark)),
                ],
              ),
              if (widget.chatInitFailed && widget.onRetryChatInit != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Material(
                    color: Colors.amber.shade700,
                    child: InkWell(
                      onTap: widget.onRetryChatInit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                AppLanguageService.instance.t('chat_connection_failed_retry'),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Call overlay is now global in HomeShell so it shows on top of all tabs/screens
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, bool isWide, bool isDark) {
    // Website: w-full md:w-[480px]
    final width = isWide ? 480.0 : MediaQuery.sizeOf(context).width;
    final availableHeight = MediaQuery.sizeOf(context).height - MediaQuery.paddingOf(context).vertical;
    return SizedBox(
      width: width,
      height: availableHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildChatSidebarTopSection(context, isWide, isDark),
          Expanded(child: _buildChatListCard(context, isWide, isDark)),
        ],
      ),
    );
  }

  /// Website: one div pl-5 pr-5 md:pr-12 pt-6 pb-2 shrink-0 containing:
  /// 1) flex justify-between items-center mb-6 relative h-14 (search | HELLO+name | notifications)
  /// 2) flex items-center gap-5 mb-4 overflow-x-auto no-scrollbar pb-2 (Add Story + stories)
  Widget _buildChatSidebarTopSection(BuildContext context, bool isWide, bool isDark) {
    const padL = 20.0; // pl-5
    final padR = isWide ? 48.0 : 20.0; // pr-5 md:pr-12
    const padT = 24.0; // pt-6
    const padB = 8.0; // pb-2
    const buttonSize = 38.0; // search & notification
    const rowHeight = 64.0; // extra height to fit mood line on small screens

    return Padding(
      padding: EdgeInsets.only(left: padL, right: padR, top: padT, bottom: padB),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: search | HELLO + name (center, mx-4) | notifications — mb-6
          SizedBox(
            height: rowHeight,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    if (widget.onOpenGlobalSearch != null) {
                      widget.onOpenGlobalSearch!();
                    } else {
                      setState(() => _showLocalSearch = !_showLocalSearch);
                    }
                  },
                  child: Container(
                    width: buttonSize,
                    height: buttonSize,
                    decoration: BoxDecoration(
                      color: _showLocalSearch
                          ? (isDark ? Colors.white : BondhuTokens.primary)
                          : (isDark ? BondhuTokens.surfaceDark : const Color(0xFFE5E7EB)),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB),
                      ),
                    ),
                    child: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: _showLocalSearch
                          ? (isDark ? Colors.black : Colors.white)
                          : (isDark ? const Color(0xFF71717A) : const Color(0xFF4B5563)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // HELLO + name (hidden when search)
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _showLocalSearch ? 0 : 1,
                        child: ValueListenableBuilder<String>(
                          valueListenable: MoodStatusService.instance.currentMoodKey,
                          builder: (context, moodKey, child) {
                            final moodEmoji = MoodStatusService.instance.displayEmoji;
                            final moodLabel = MoodStatusService.instance.displayLabel;
                            final hasMood = moodKey.isNotEmpty && moodLabel.isNotEmpty;
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  AppLanguageService.instance.t('hello'),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF6B7280),
                                    letterSpacing: 3.6,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 160,
                                  child: Text(
                                    (widget.userName ?? AppLanguageService.instance.t('user')).toLowerCase(),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                                      height: 1.15,
                                      letterSpacing: -0.3,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                if (hasMood) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '${moodEmoji.isNotEmpty ? '$moodEmoji  ' : ''}$moodLabel',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                      // Search input (visible when search)
                      if (_showLocalSearch)
                        TextField(
                          autofocus: true,
                          onChanged: (v) => setState(() => _searchQuery = v),
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF111827),
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: AppLanguageService.instance.t('search_chats'),
                            hintStyle: TextStyle(
                              color: isDark ? BondhuTokens.textMutedDark : const Color(0xFF6B7280),
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF121212) : const Color(0xFFE5E7EB),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                StreamBuilder<List<AppNotification>>(
                  stream: NotificationService.instance.stream,
                  initialData: NotificationService.instance.list,
                  builder: (context, snap) {
                    final unread = (snap.data ?? []).where((n) => !n.read).length;
                    return GestureDetector(
                      onTap: () {
                        if (widget.onOpenNotifications != null) {
                          widget.onOpenNotifications!();
                        } else {
                          _showNotificationPanel(context, isDark);
                        }
                      },
                      child: Container(
                        width: buttonSize,
                        height: buttonSize,
                        decoration: BoxDecoration(
                          color: isDark ? BondhuTokens.surfaceDark : const Color(0xFFE5E7EB),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB),
                          ),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Center(
                              child: Icon(
                                Icons.notifications_rounded,
                                size: 20,
                                color: isDark ? const Color(0xFF71717A) : const Color(0xFF4B5563),
                              ),
                            ),
                            if (unread > 0)
                              Positioned(
                                right: 1,
                                top: 1,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                  constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                                  decoration: BoxDecoration(
                                    color: BondhuTokens.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    unread > 99 ? '99+' : '$unread',
                                    style: const TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          // Stories section – match FeedView story layout for consistency
          _buildChatStoriesRow(context, isDark),
          const SizedBox(height: 16), // mb-4
        ],
      ),
    );
  }

  /// Stories row styled to match the Feed screen (horizontal cards).
  Widget _buildChatStoriesRow(BuildContext context, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: BondhuTokens.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Stories',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                ),
              ),
            ],
          ),
        ),
        ScrollConfiguration(
          behavior: _NoScrollbarScrollBehavior(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildChatAddStory(isDark),
                if (_storiesLoading) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: BondhuTokens.feedStoryBoxWidth,
                    height: BondhuTokens.feedStoryBoxHeight,
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ] else ...[
                  ..._stories.asMap().entries.map((entry) {
                    final index = entry.key;
                    final story = entry.value;
                    return Padding(
                      padding: EdgeInsets.only(left: index == 0 ? 10 : 0, right: 10),
                      child: _buildChatStoryBox(story, index, isDark),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAndUploadStory() async {
    final email = widget.currentUser.email?.trim();
    if (email == null || email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLanguageService.instance.t('please_sign_in_add_story')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    try {
      final picker = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picker == null || !mounted) return;
      setState(() => _addingStory = true);
      String? url;
      if (kIsWeb) {
        final bytes = await picker.readAsBytes();
        if (!mounted) return;
        final ext = picker.name.split('.').last;
        url = await uploadFileFromBytes(bytes, 'story_${DateTime.now().millisecondsSinceEpoch}.${ext.isEmpty ? "jpg" : ext}');
      } else {
        url = await uploadFile(picker.path);
      }
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLanguageService.instance.t('could_not_upload_image_story')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await createStory(userId: email, mediaUrl: url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageService.instance.t('story_added')), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
        );
        _loadStories();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageService.instance.t('failed_add_story')), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _addingStory = false);
    }
  }

  void _showNotificationPanel(BuildContext context, bool isDark) {
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    if (isWide) {
      showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 560),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: StreamBuilder<List<AppNotification>>(
                stream: NotificationService.instance.stream,
                initialData: NotificationService.instance.list,
                builder: (_, snap) => NotificationPanel(
                  notifications: snap.data ?? [],
                  isDark: isDark,
                  onMarkAllRead: () => NotificationService.instance.markAllRead(),
                  onTap: (n) {
                    NotificationService.instance.markRead(n.id);
                    Navigator.of(ctx).pop();
                    if (n.chatId != null) {
                      try {
                        final chat = widget.chatService.chats.firstWhere((c) => c.id == n.chatId);
                        _openChat(chat);
                      } catch (_) {}
                    }
                  },
                  onClose: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, scrollController) => StreamBuilder<List<AppNotification>>(
            stream: NotificationService.instance.stream,
            initialData: NotificationService.instance.list,
            builder: (_, snap) => NotificationPanel(
              notifications: snap.data ?? [],
              isDark: isDark,
              onMarkAllRead: () => NotificationService.instance.markAllRead(),
              onTap: (n) {
                NotificationService.instance.markRead(n.id);
                Navigator.of(ctx).pop();
                if (n.chatId != null) {
                  try {
                    final chat = widget.chatService.chats.firstWhere((c) => c.id == n.chatId);
                    _openChat(chat);
                  } catch (_) {}
                }
              },
              onClose: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      );
    }
  }

  void _openStory(int index) {
    if (_stories.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      barrierDismissible: false,
      builder: (ctx) => StoryOverlay(
        stories: _stories,
        initialIndex: index,
        currentUserEmail: widget.currentUser.email,
        currentUserName: widget.currentUser.name ?? widget.userName,
        currentUserAvatar: widget.currentUser.avatar,
        isDark: widget.isDark,
        onClose: () => Navigator.of(ctx).pop(),
        onStoriesUpdated: () {
          _loadStories();
        },
      ),
    );
  }

  /// "Add Story" card – compact version shared with Feed styling.
  Widget _buildChatAddStory(bool isDark) {
    final w = BondhuTokens.feedStoryBoxWidth;
    final h = BondhuTokens.feedStoryBoxHeight;
    final r = BondhuTokens.feedStoryBoxRadius;
    return SizedBox(
      width: w,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _addingStory ? null : _pickAndUploadStory,
          borderRadius: BorderRadius.circular(r),
          child: Container(
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              border: Border.all(
                color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7),
                width: 1.5,
              ),
              color: isDark
                  ? BondhuTokens.surfaceDarkCard.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.85),
            ),
            child: Center(
              child: _addingStory
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppLanguageService.instance.t('add_story'),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: isDark ? const Color(0xFF71717A) : const Color(0xFF71717A),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Individual story card – mirrors FeedView story box styling.
  Widget _buildChatStoryBox(StoryItem story, int index, bool isDark) {
    final w = BondhuTokens.feedStoryBoxWidth;
    final h = BondhuTokens.feedStoryBoxHeight;
    final r = BondhuTokens.feedStoryBoxRadius;
    final avatarSize = BondhuTokens.feedStoryBoxAvatarSize;
    final hasMedia = story.mediaUrl.isNotEmpty;
    final myEmail = widget.currentUser.email?.trim().toLowerCase() ?? '';
    final isMine = myEmail.isNotEmpty && story.userId.toLowerCase() == myEmail;
    return SizedBox(
      width: w,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openStory(index),
        child: Container(
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0).withValues(alpha: 0.8),
              width: 1,
            ),
            boxShadow: isDark ? BondhuTokens.cardShadowDark : BondhuTokens.cardShadowLight,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(r - 1),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasMedia)
                  _premiumNetworkImage(
                    story.mediaUrl,
                    fit: BoxFit.cover,
                    cacheWidth: 136,
                    cacheHeight: 204,
                    loading: Container(
                      color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE2E8F0),
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                    error: _chatStoryBoxPlaceholder(isDark),
                  )
                else
                  _chatStoryBoxPlaceholder(isDark),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 36,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 3,
                  right: 3,
                  bottom: 4,
                  child: Text(
                    story.userName,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Positioned(
                  top: 5,
                  left: 5,
                  child: Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: _premiumNetworkImage(
                        story.avatar,
                        fit: BoxFit.cover,
                        cacheWidth: 64,
                        cacheHeight: 64,
                        loading: Container(
                          color: isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB),
                          child: const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        error: Icon(Icons.person_rounded, size: avatarSize * 0.5, color: BondhuTokens.textMutedDark),
                      ),
                    ),
                  ),
                ),
                // Insights badge for your own story (views / likes) in chat tab.
                if (isMine && (story.views.isNotEmpty || story.likes.isNotEmpty))
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility_rounded, size: 13, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            '${story.views.length}',
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                          if (story.likes.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.favorite_rounded, size: 12, color: Colors.redAccent),
                            const SizedBox(width: 2),
                            Text(
                              '${story.likes.length}',
                              style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                          ],
                        ],
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

  Widget _chatStoryBoxPlaceholder(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF27272A), const Color(0xFF1F1F23)]
              : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 24,
          color: isDark ? BondhuTokens.textMutedDark : const Color(0xFF94A3B8),
        ),
      ),
    );
  }

  Widget _premiumNetworkImage(
    String url, {
    required BoxFit fit,
    int? cacheWidth,
    int? cacheHeight,
    Widget? loading,
    Widget? error,
  }) {
    return Image.network(
      url,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        final visible = wasSynchronouslyLoaded || frame != null;
        return AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: child,
        );
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return loading ?? const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
      errorBuilder: (_, _, _) => error ?? const Icon(Icons.image_not_supported),
    );
  }
  // _storyCircle was replaced by card-style stories to match FeedView.

  Widget _buildChatListCard(BuildContext context, bool isWide, bool isDark) {
    final marginLeft = 20.0;
    final marginRight = isWide ? 48.0 : 20.0;
    final marginBottom = 16.0;
    return Padding(
      padding: EdgeInsets.only(left: marginLeft, right: marginRight, bottom: marginBottom),
      child: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: isDark
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFF8FDFB),
                    Colors.white,
                    const Color(0xFFF2FBF8),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
          color: isDark ? BondhuTokens.surfaceDarkCard : null,
          borderRadius: BorderRadius.circular(BondhuTokens.radius2xl),
          border: Border.all(
            color: isDark ? BondhuTokens.borderDark.withValues(alpha: 0.6) : const Color(0xFFE0EDE9),
            width: 1,
          ),
          boxShadow: [
            ...(isDark ? BondhuTokens.cardShadowDark : BondhuTokens.cardShadowLight),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
              blurRadius: 20,
              spreadRadius: -2,
              offset: const Offset(0, 6),
            ),
            if (isDark)
              BoxShadow(
                color: BondhuTokens.primary.withValues(alpha: 0.12),
                blurRadius: 24,
                spreadRadius: -4,
                offset: Offset.zero,
              ),
            if (!isDark)
              BoxShadow(
                color: BondhuTokens.primary.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                // Website: flex gap-2 mb-4 overflow-x-auto no-scrollbar items-center shrink-0 (height ~39px)
                SizedBox(
                  height: 39,
                  child: ScrollConfiguration(
                    behavior: _NoScrollbarScrollBehavior(),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildHiddenChatsChip(context, isDark),
                          const SizedBox(width: 8), // gap-2
                          _actionChip(context, label: AppLanguageService.instance.t('new_group'), icon: Icons.group_add, color: const Color(0xFF4F46E5), bgColor: const Color(0xFFEEF2FF), isDark: isDark, onTap: () => _showNewGroupModal(context, isDark)),
                          const SizedBox(width: 8),
                          _actionChip(context, label: AppLanguageService.instance.t('global'), icon: Icons.public, color: const Color(0xFF7C3AED), bgColor: const Color(0xFFF3E8FF), isDark: isDark, onTap: _ensureGlobalAndOpen),
                          const SizedBox(width: 8),
                          _actionChip(context, label: AppLanguageService.instance.t('contacts'), icon: Icons.contacts_outlined, color: const Color(0xFFEA580C), bgColor: const Color(0xFFFFEDD5), isDark: isDark, onTap: () => _openContactPage(context, isDark)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16), // mb-4
                ValueListenableBuilder<String>(
                  valueListenable: MoodStatusService.instance.currentMoodKey,
                  builder: (context, moodKey, child) {
                    final showSupport =
                        moodKey == 'tired' || moodKey == 'need_support';
                    if (!showSupport) return const SizedBox.shrink();
                    final supportBg = isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF1F5F9);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: supportBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('💙', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppLanguageService.instance.t('mood_support_title'),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    AppLanguageService.instance.t('mood_support_body'),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await _loadStories();
                      if (mounted) setState(() {});
                    },
                    color: BondhuTokens.primary,
                    child: ValueListenableBuilder<Map<String, String>>(
                      valueListenable: NicknameService.instance.nicknames,
                      builder: (context, nicknames, child) => _buildChatList(isDark),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ),
    );
  }

  /// Modern chip for Hidden Chats: gradient border, soft glow, stays in the filter row.
  Widget _buildHiddenChatsChip(BuildContext context, bool isDark) {
    const radius = 14.0;
    const padH = 18.0;
    const padV = 12.0;
    final label = AppLanguageService.instance.t('private');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openHiddenChatsScreen(context, isDark),
        borderRadius: BorderRadius.circular(radius),
        hoverColor: BondhuTokens.primary.withValues(alpha: 0.12),
        highlightColor: BondhuTokens.primary.withValues(alpha: 0.18),
        splashColor: BondhuTokens.primary.withValues(alpha: 0.25),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          decoration: BoxDecoration(
            gradient: isDark
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      BondhuTokens.primary.withValues(alpha: 0.18),
                      BondhuTokens.primary.withValues(alpha: 0.08),
                    ],
                  )
                : null,
            color: isDark ? null : BondhuTokens.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: BondhuTokens.primary.withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: BondhuTokens.primary.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded, size: 16, color: BondhuTokens.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: BondhuTokens.primary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Match web: Private = green border/transparent; New Group = indigo; Global = violet; Contacts = orange.
  Widget _actionChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    bool isPrimary = false,
    Color? color,
    Color? bgColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    // Web: px-4 py-2.5 rounded-xl text-[11px] font-bold
    const radius = 12.0; // rounded-xl
    const padH = 16.0;   // px-4
    const padV = 10.0;   // py-2.5
    const fontSize = 11.0;

    final Color effectiveBg;
    final Color effectiveColor;
    final Color? borderColor;
    final List<BoxShadow>? shadow;

    if (isPrimary) {
      // Private: border-[#00C896] bg-transparent dark:bg-black text-[#00C896] shadow-[0_0_10px_rgba(0,200,150,0.1)]
      effectiveBg = isDark ? Colors.black : Colors.transparent;
      effectiveColor = BondhuTokens.primary;
      borderColor = BondhuTokens.primary;
      shadow = [BoxShadow(color: BondhuTokens.primary.withValues(alpha: 0.1), blurRadius: 10, offset: Offset.zero)];
    } else {
      // Same colors in light and dark: New Group #EEF2FF/#4F46E5; Global #F3E8FF/#7C3AED; Contacts #FFEDD5/#EA580C
      effectiveBg = bgColor ?? const Color(0xFFF4F4F6);
      effectiveColor = color ?? const Color(0xFF4B5563);
      borderColor = null;
      shadow = null;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        hoverColor: isPrimary ? BondhuTokens.primary.withValues(alpha: 0.15) : null,
        highlightColor: isPrimary ? BondhuTokens.primary.withValues(alpha: 0.2) : null,
        splashColor: isPrimary ? BondhuTokens.primary.withValues(alpha: 0.25) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          decoration: BoxDecoration(
            color: effectiveBg,
            borderRadius: BorderRadius.circular(radius),
            border: borderColor != null ? Border.all(color: borderColor, width: 1) : null,
            boxShadow: shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: effectiveColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(fontSize: fontSize, fontWeight: FontWeight.w700, color: effectiveColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chatListTile(
    BuildContext context,
    ChatItem chat,
    bool isDark, {
    bool isSelected = false,
    bool isInArchivedSection = false,
    VoidCallback? onArchiveSnooze,
  }) {
    const avatarSize = 48.0;
    const tileRadius = 18.0;
    final hoverAndSelectedBg = isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF8F8F9);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openChat(chat),
        onLongPress: onArchiveSnooze,
        borderRadius: BorderRadius.circular(tileRadius),
        hoverColor: hoverAndSelectedBg,
        focusColor: hoverAndSelectedBg,
        highlightColor: hoverAndSelectedBg.withValues(alpha: 0.5),
        splashColor: BondhuTokens.primary.withValues(alpha: 0.15),
        child: AnimatedContainer(
          duration: BondhuTokens.motionFast,
          curve: BondhuTokens.motionEase,
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.all(12), // p-3
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF1F5F9))
                : null,
            borderRadius: BorderRadius.circular(tileRadius),
            border: Border.all(
              color: isSelected
                  ? BondhuTokens.primary.withValues(alpha: isDark ? 0.35 : 0.28)
                  : Colors.transparent,
              width: 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: BondhuTokens.primary.withValues(alpha: isDark ? 0.10 : 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  chat.isGlobal
                      ? BondhuAppLogo(size: avatarSize, circular: false, iconScale: 0.48)
                      : CircleAvatar(
                          radius: avatarSize / 2,
                          backgroundColor: isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFE5E7EB),
                          backgroundImage: chat.avatar != null && chat.avatar!.isNotEmpty
                              ? NetworkImage(chat.avatar!, scale: 1.0) // Explicit scale
                              : null,
                          child: chat.avatar == null ? Icon(Icons.person, color: BondhuTokens.textMutedDark, size: 20) : null,
                        ),
                  if (chat.unread > 0)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12, // w-3
                        height: 12, // h-3
                        decoration: BoxDecoration(
                          color: BondhuTokens.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? BondhuTokens.bgDark : BondhuTokens.surfaceLight,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14), // ml-3.5
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.isGlobal ? AppLanguageService.instance.t('global_chat') : NicknameService.instance.getDisplayName(chat),
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: isDark ? Colors.white : const Color(0xFF111827),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          chat.lastTime ?? '',
                          style: TextStyle(
                            fontSize: 10, // text-[10px]
                            fontWeight: FontWeight.w500,
                            color: isDark ? BondhuTokens.textMutedDark : const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2), // mb-0.5
                    Row(
                      children: [
                        if (!chat.isGlobal) ...[
                          Icon(Icons.lock_rounded, size: 12, color: isDark ? const Color(0xFF71717A) : const Color(0xFF6B7280)),
                          const SizedBox(width: 4),
                          if (chat.muteMessages) ...[
                            Icon(
                              Icons.notifications_off_rounded,
                              size: 12,
                              color: isDark ? const Color(0xFF71717A) : const Color(0xFF6B7280),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ],
                        Expanded(
                          child: Text(
                            chat.lastMessage?.isNotEmpty == true
                                ? chat.lastMessage!
                                : (!chat.isGlobal ? AppLanguageService.instance.t('encrypted_message') : ''),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: chat.unread > 0 ? FontWeight.w700 : FontWeight.w500,
                              color: chat.unread > 0
                                  ? (isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight)
                                  : (isDark ? const Color(0xFF71717A) : const Color(0xFF6B7280)),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (chat.unread > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: BondhuTokens.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              chat.unread > 99 ? '99+' : '${chat.unread}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ],
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

  /// Website (desktop only): flex-1 h-full md:rounded-l-[40px] md:-ml-4 overflow-hidden flex flex-col
  /// bg-gray-100 dark:bg-black md:shadow-[-30px_0_60px_...] md:border-l border-gray-200 dark:border-white/20
  /// Inner: h-full w-full flex flex-col items-center justify-center bg-gray-200 dark:bg-black select-none opacity-60 dark:opacity-20
  /// Text: SELECT A CONVERSATION
  Widget _buildEmptyState(BuildContext context, bool isDark) {
    const radius = 40.0; // rounded-l-[40px]
    const overlapLeft = 16.0; // md:-ml-4 — use Transform because Container margin must be non-negative

    return Transform.translate(
      offset: const Offset(-overlapLeft, 0),
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(radius)),
        child: Container(
          decoration: BoxDecoration(
          color: isDark ? BondhuTokens.bgDark : const Color(0xFFF4F4F5),
          border: Border(
            left: BorderSide(
              color: isDark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFE5E7EB), // border-gray-200 dark:border-white/20
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.9 : 0.15),
              blurRadius: 60,
              offset: const Offset(-30, 0), // -30px 0 60px
            ),
          ],
        ),
        child: IgnorePointer(
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? BondhuTokens.surfaceDark : const Color(0xFFE5E7EB),
            ),
            child: Opacity(
              opacity: isDark ? 0.2 : 0.6, // opacity-60 dark:opacity-20
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppLanguageService.instance.t('select_conversation'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

}

/// Hides scrollbar for horizontal chip row (website: no-scrollbar).
class _NoScrollbarScrollBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}
