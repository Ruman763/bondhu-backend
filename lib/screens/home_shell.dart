import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../app_animations.dart';
import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/supabase_service.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart' show ChatService, ConnectionStatus;
import '../services/chat_notes_service.dart';
import '../services/draft_service.dart';
import '../services/notification_service.dart';
import '../services/pinned_message_service.dart';
import '../services/privacy_settings_service.dart';
import '../services/schedule_message_service.dart';
import '../services/push_notification_service.dart' show PushNotificationService;
import '../services/custom_call_message_service.dart';
import '../widgets/bondhu_app_logo.dart';
import 'call_overlay.dart';
import 'custom_call_message_overlay.dart';
import 'chat_view.dart';
import 'feed_view.dart';
import 'global_search_overlay.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'wallet_view.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.currentUser,
    required this.isDark,
    required this.onDarkModeChanged,
    required this.onLogout,
    required this.onProfileUpdated,
  });

  final AuthUser currentUser;
  final bool isDark;
  final ValueChanged<bool> onDarkModeChanged;
  final Future<void> Function() onLogout;
  final ValueChanged<AuthUser> onProfileUpdated;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  /// When on Feed tab: 0=Home, 1=Videos, 2=Profile. Shown in bottom bar instead of Chat/Wallet.
  int _feedPillIndex = 0;
  /// Bump when switching to Feed tab so FeedView reloads stories (e.g. after adding from Chat).
  int _feedRefreshStoriesTrigger = 0;
  bool _showGlobalSearch = false;
  bool _isAppInForeground = true;
  bool _chatInitFailed = false;
  late final ChatService _chatService = ChatService();
  late final CallService _callService;
  final ValueNotifier<String?> pushOpenChatId = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final u = widget.currentUser;
    _callService = CallService(
      chatService: _chatService,
      onCallFailed: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final reason = _callService.lastCallFailureReason;
          final key = reason == 'socket'
              ? 'call_not_ready'
              : reason == 'permission'
                  ? 'call_permission_required'
                  : 'call_failed_try_again';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLanguageService.instance.t(key)),
              behavior: SnackBarBehavior.floating,
            ),
          );
        });
      },
      onCallEnded: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLanguageService.instance.t('call_ended')),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        });
      },
    );
    _callService.onShowIncomingCallNotification = (String callerName, String callerId, String callType) {
      if (!_isAppInForeground && PushNotificationService.instance.isInitialized) {
        PushNotificationService.instance.showIncomingCallNotification(
          callerName: callerName,
          callerId: callerId,
          callType: callType,
        );
      }
    };
    _callService.activeCallNotifier.addListener(_onActiveCallChanged);
    // Only add in-app notification (and vibration) when app is in background — like WhatsApp.
    _chatService.onIncomingMessageWhenBackground = (String chatId, String chatName, String messageText, String? avatarUrl) {
      if (!_isAppInForeground) {
        NotificationService.instance.addMessageNotification(
          chatId: chatId,
          chatName: chatName,
          messageText: messageText,
          avatarUrl: avatarUrl,
        );
      }
    };
    _chatService.connectionStatusStream.listen((status) {
      if (status == ConnectionStatus.connected) _callService.attachSocket(_chatService.socket);
    }, cancelOnError: false);
    // Defer chat init to after first frame so UI paints immediately and app doesn't freeze during socket connect.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await PrivacySettingsService.instance.load();
        _chatService.init(u.email ?? '', u.name ?? 'User');
        _callService.attachSocket(_chatService.socket);
        await CustomCallMessageService.instance.setAccountScope(u.email);
        await DraftService.instance.setAccountScope(u.email);
        await ChatNotesService.instance.setAccountScope(u.email);
        ScheduleMessageService.instance.load();
        ScheduleMessageService.instance.onSendScheduled = (chatId, text, type, {replyToId, replyToText}) {
          _chatService.sendMessage(chatId, text, type, replyToId: replyToId, replyToText: replyToText);
        };
        ScheduleMessageService.instance.startTimer();
        PinnedMessageService.instance.load();
        DraftService.instance.load();
        ChatNotesService.instance.load();
        if (mounted) setState(() => _chatInitFailed = false);
      } catch (e, st) {
        debugPrint('[Bondhu Chat] init() failed: $e');
        debugPrintStack(stackTrace: st);
        if (mounted) setState(() => _chatInitFailed = true);
      }
    });
    // Defer non-critical work so first paint is fast on low-end devices
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      NotificationService.instance.setAccountScope(u.email);
      // Push init is deferred in main(); run after it may have completed
      PushNotificationService.init().then((_) {
        if (!mounted) return;
        if (PushNotificationService.instance.isInitialized) {
          PushNotificationService.instance.registerTokenWithBackend(
            u.email ?? '',
            (String token) {
              _chatService.registerFcmToken(token);
              updateProfileFcmToken(u.email ?? '', token);
            },
          );
          PushNotificationService.instance.onNotificationTapped = (Map<String, dynamic>? data) {
            if (data == null || data.isEmpty) return;
            final isCall = data['type'] == 'call';
            final chatId = data['chatId'] as String?;
            final actionId = data['notificationActionId'] as String?;
            if (isCall && chatId != null && chatId.isNotEmpty) {
              if (actionId == 'decline') {
                PushNotificationService.instance.cancelIncomingCallNotification();
                _callService.setPendingDeclineFromNotification(chatId);
                _callService.endCall(emitEvent: false);
              } else {
                setState(() => _index = 0);
                final callerName = (data['body'] as String?)?.trim().isNotEmpty == true
                    ? (data['body'] as String).trim()
                    : (data['title'] as String?) ?? 'Unknown';
                final callType = (data['callType'] as String?) ?? 'audio';
                _callService.showIncomingCallFromNotification(chatId, callerName, callType);
              }
            } else if (chatId != null && chatId.isNotEmpty) {
              setState(() => _index = 0);
              pushOpenChatId.value = chatId;
            }
          };
          // Defer so ChatView can mount and register its listener (fixes "notification tap → loading" when app was cold-started).
          Future<void>.delayed(const Duration(milliseconds: 400), () {
            if (!mounted) return;
            PushNotificationService.instance.deliverPendingLaunchTap();
          });
        }
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _isAppInForeground = state == AppLifecycleState.resumed;
  }

  void _onActiveCallChanged() {
    final call = _callService.activeCallNotifier.value;
    if (call == null || call.status != 'incoming') {
      PushNotificationService.instance.cancelIncomingCallNotification();
    }
  }

  Future<void> _retryChatInit() async {
    setState(() => _chatInitFailed = false);
    final u = widget.currentUser;
    try {
      _chatService.init(u.email ?? '', u.name ?? 'User');
      _callService.attachSocket(_chatService.socket);
      if (mounted) setState(() => _chatInitFailed = false);
    } catch (e, st) {
      debugPrint('[Bondhu Chat] retry init failed: $e');
      debugPrintStack(stackTrace: st);
      if (mounted) setState(() => _chatInitFailed = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callService.activeCallNotifier.removeListener(_onActiveCallChanged);
    _callService.dispose();
    _chatService.disconnect();
    super.dispose();
  }

  static const _navItems = [
    (Icons.chat_bubble_outline, Icons.chat_bubble, 'Chat'),
    (Icons.layers_outlined, Icons.layers, 'Feed'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Wallet'),
  ];

  /// Builds all tab pages once; [IndexedStack] shows the one at [_index] and keeps others alive.
  Widget _buildContent() {
    final u = widget.currentUser;
    final pages = <Widget>[
      ChatView(
        key: const ValueKey<String>('chat'),
        currentUser: u,
        chatService: _chatService,
        callService: _callService,
        userName: u.name,
        userAvatarUrl: u.avatar,
        isDark: widget.isDark,
        pushOpenChatId: pushOpenChatId,
        onOpenGlobalSearch: () => setState(() => _showGlobalSearch = true),
        chatInitFailed: _chatInitFailed,
        onRetryChatInit: _retryChatInit,
        onOpenNotifications: _openNotificationsScreen,
      ),
      FeedView(
        key: const ValueKey<String>('feed'),
        currentUser: u,
        userName: u.name,
        userAvatarUrl: u.avatar,
        isDark: widget.isDark,
        onProfileUpdated: widget.onProfileUpdated,
        onNavigateToChat: (String? userId) {
          setState(() => _index = 0);
          pushOpenChatId.value = userId;
        },
        onOpenNotifications: _openNotificationsScreen,
        feedPillIndex: _index == 1 ? _feedPillIndex : null,
        onFeedPillChanged: _index == 1 ? (int i) => setState(() => _feedPillIndex = i) : null,
        refreshStoriesTrigger: _feedRefreshStoriesTrigger,
      ),
      WalletView(
        key: const ValueKey<String>('wallet'),
        userName: u.name,
        isDark: widget.isDark,
        onNavigateToChat: () => setState(() => _index = 0),
      ),
    ];
    return Stack(
      fit: StackFit.expand,
      children: List.generate(pages.length, (i) {
        final selected = _index == i;
        return IgnorePointer(
          ignoring: !selected,
          child: AnimatedOpacity(
            opacity: selected ? 1 : 0,
            duration: BondhuTokens.motionFast,
            curve: BondhuTokens.motionEase,
            child: AnimatedSlide(
              offset: selected ? Offset.zero : const Offset(0.02, 0),
              duration: BondhuTokens.motionNormal,
              curve: BondhuTokens.motionEmphasized,
              child: pages[i],
            ),
          ),
        );
      }),
    );
  }

  /// Push a full-screen notifications view from anywhere (e.g. feed, chat).
  void _openNotificationsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(
          isDark: widget.isDark,
          onNotificationTap: (n) {
            NotificationService.instance.markRead(n.id);
            Navigator.of(context).pop();
            setState(() => _index = 0);
            if (n.chatId != null && n.chatId!.isNotEmpty) {
              pushOpenChatId.value = n.chatId;
            }
          },
        ),
      ),
    );
  }

  /// One consistent background for the whole app: tokens only (no per-screen color mix).
  static BoxDecoration _shellBackgroundDecoration(bool isDark) {
    return BoxDecoration(
      color: isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    final isDark = widget.isDark;

    if (isWide) {
      return Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Container(decoration: _shellBackgroundDecoration(isDark)),
            ),
            Row(
              children: [
                _buildDesktopSidebar(context, isWide),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: _buildContent(),
                  ),
                ),
              ],
            ),
            CallOverlay(callService: _callService, isDark: isDark),
            CustomCallMessageOverlay(callService: _callService, isDark: isDark),
            if (_showGlobalSearch) _buildGlobalSearchOverlay(isDark),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Container(decoration: _shellBackgroundDecoration(isDark)),
          ),
          _buildContent(),
          CallOverlay(callService: _callService, isDark: isDark),
          CustomCallMessageOverlay(callService: _callService, isDark: isDark),
          if (_showGlobalSearch) _buildGlobalSearchOverlay(isDark),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildGlobalSearchOverlay(bool isDark) {
    return GlobalSearchOverlay(
      isDark: isDark,
      chatList: List.from(_chatService.chats),
      currentUserEmail: widget.currentUser.email,
      onSelectPerson: (ProfileDoc p) {
        setState(() {
          _showGlobalSearch = false;
          _index = 0;
        });
        final displayName = p.name.isNotEmpty ? p.name : ChatService.formatName(p.userId);
        pushOpenChatId.value = '${p.userId}|$displayName';
      },
      onSelectChat: (chat) {
        setState(() {
          _showGlobalSearch = false;
          _index = 0;
        });
        pushOpenChatId.value = chat.id;
      },
      onClose: () => setState(() => _showGlobalSearch = false),
    );
  }

  Widget _buildDesktopSidebar(BuildContext context, bool isWide) {
    return Container(
      width: BondhuTokens.sidebarWidth,
      margin: EdgeInsets.only(
        left: BondhuTokens.sidebarLeft,
        top: BondhuTokens.sidebarTop,
        bottom: BondhuTokens.sidebarBottom,
      ),
      decoration: BoxDecoration(
        color: widget.isDark ? BondhuTokens.surfaceDark : BondhuTokens.surfaceLight,
        borderRadius: BorderRadius.circular(BondhuTokens.sidebarRadius),
        border: Border.all(
          color: widget.isDark ? BondhuTokens.borderDark : BondhuTokens.borderLight,
        ),
        boxShadow: BondhuTokens.sidebarShadow,
      ),
      child: _sidebarContent(context),
    );
  }

  Widget _sidebarContent(BuildContext context) {
    return Padding(
        padding: EdgeInsets.symmetric(horizontal: BondhuTokens.sidebarPaddingX),
        child: Column(
          children: [
            SizedBox(height: BondhuTokens.sidebarPaddingY),
            Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _index = 0),
                  borderRadius: BorderRadius.circular(BondhuTokens.sidebarLogoRadius),
                  child: const BondhuAppLogo(size: BondhuTokens.sidebarLogoSize),
                ),
              ),
            ),
            SizedBox(height: BondhuTokens.sidebarLogoMarginBottom),
            ...List.generate(_navItems.length, (i) {
              final (outline, filled, _) = _navItems[i];
              final selected = _index == i;
              return Padding(
                key: ValueKey('sidebar_nav_$i'),
                padding: EdgeInsets.symmetric(vertical: BondhuTokens.sidebarNavGap / 2),
                child: Material(
                  color: Colors.transparent,
                    child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _index = i;
                        if (i == 1) _feedRefreshStoriesTrigger = DateTime.now().millisecondsSinceEpoch;
                      });
                    },
                    borderRadius: BorderRadius.circular(BondhuTokens.radiusLg),
                    child: Container(
                      width: BondhuTokens.sidebarNavItemSize,
                      height: BondhuTokens.sidebarNavItemSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? BondhuTokens.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(BondhuTokens.radiusLg),
                      ),
                      child: Icon(
                        selected ? filled : outline,
                        size: BondhuTokens.fontSizeXl,
                        color: selected
                            ? Colors.white
                            : (widget.isDark ? BondhuTokens.textMutedDarkAlt : BondhuTokens.textMutedLight),
                      ),
                    ),
                  ),
                ),
              );
            }),
            const Spacer(),
            Center(
                child: GestureDetector(
                  onTap: () => _showSettingsModal(context),
                  child: CircleAvatar(
                    radius: BondhuTokens.sidebarAvatarSize / 2,
                    backgroundColor: widget.isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.borderLight,
                  backgroundImage: widget.currentUser.avatar != null &&
                          widget.currentUser.avatar!.isNotEmpty
                      ? NetworkImage(widget.currentUser.avatar!, scale: 1.0)
                      : null,
                  child: widget.currentUser.avatar == null ||
                          widget.currentUser.avatar!.isEmpty
                      ? Icon(
                          Icons.person,
                          color: widget.isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                        )
                      : null,
                ),
              ),
            ),
            SizedBox(height: BondhuTokens.sidebarPaddingY),
          ],
        ),
      );
  }

  Widget _buildBottomNav(BuildContext context) {
    if (_index == 1) return _buildFeedBottomBar(context);
    return _buildMainBottomNav(context);
  }

  /// When on Feed: Back (left) + Home, Videos, Profile (no Chat/Wallet).
  Widget _buildFeedBottomBar(BuildContext context) {
    const double navHeight = 76.0;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: navHeight + bottomPadding,
      decoration: BoxDecoration(
        color: widget.isDark ? BondhuTokens.surfaceDark : BondhuTokens.surfaceLight,
        border: Border(
          top: BorderSide(
            color: widget.isDark ? BondhuTokens.borderDark : BondhuTokens.borderLight,
          ),
        ),
      ),
      child: RepaintBoundary(
        child: _wrapWithBlurIfWeb(
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: _premiumFeedNavItem(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: AppLanguageService.instance.t('nav_chat'),
                    selected: false,
                    onTap: () => setState(() => _index = 0),
                  ),
                ),
                Expanded(
                  child: _premiumFeedNavItem(
                    icon: _feedPillIndex == 0 ? Icons.home_rounded : Icons.home_outlined,
                    label: 'Home',
                    selected: _feedPillIndex == 0,
                    onTap: () => setState(() => _feedPillIndex = 0),
                  ),
                ),
                Expanded(
                  child: _premiumFeedNavItem(
                    icon: _feedPillIndex == 1 ? Icons.play_circle_rounded : Icons.play_circle_outline_rounded,
                    label: 'Videos',
                    selected: _feedPillIndex == 1,
                    onTap: () => setState(() => _feedPillIndex = 1),
                  ),
                ),
                Expanded(
                  child: _premiumFeedNavItem(
                    icon: _feedPillIndex == 2 ? Icons.person_rounded : Icons.person_outline_rounded,
                    label: 'Profile',
                    selected: _feedPillIndex == 2,
                    onTap: () => setState(() => _feedPillIndex = 2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// BackdropFilter causes ANR on mobile; use only on web.
  Widget _wrapWithBlurIfWeb({required Widget child}) {
    if (kIsWeb) {
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: child,
        ),
      );
    }
    return child;
  }

  Widget _buildMainBottomNav(BuildContext context) {
    const double navHeight = 76.0;
    const double avatarSize = 28.0;
    final isDark = widget.isDark;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: navHeight + bottomPadding,
      decoration: BoxDecoration(
        color: isDark ? BondhuTokens.surfaceDark : BondhuTokens.surfaceLight,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: isDark ? BondhuTokens.borderDark : BondhuTokens.borderLight,
            width: 1,
          ),
        ),
      ),
      child: RepaintBoundary(
        child: _wrapWithBlurIfWeb(
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ...List.generate(_navItems.length, (i) {
                  final (outline, filled, _) = _navItems[i];
                  final selected = _index == i;
                  return Expanded(
                    key: ValueKey('nav_$i'),
                    child: _premiumMainNavItem(
                      icon: selected ? filled : outline,
                      selected: selected,
                      onTap: () => setState(() {
                        _index = i;
                        if (i == 1) _feedRefreshStoriesTrigger = DateTime.now().millisecondsSinceEpoch;
                      }),
                    ),
                  );
                }),
                Expanded(
                  child: ScaleTap(
                    onTap: () => _showSettingsModal(context),
                    child: SizedBox(
                      height: navHeight,
                      child: Center(
                        child: CircleAvatar(
                          radius: avatarSize / 2,
                          backgroundColor: isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.borderLight,
                          backgroundImage: widget.currentUser.avatar != null &&
                                  widget.currentUser.avatar!.isNotEmpty
                              ? NetworkImage(widget.currentUser.avatar!, scale: 1.0)
                              : null,
                          child: widget.currentUser.avatar == null ||
                                  widget.currentUser.avatar!.isEmpty
                              ? Icon(
                                  Icons.person_rounded,
                                  size: 18,
                                  color: isDark ? BondhuTokens.textMutedDark : const Color(0xFF374151),
                                )
                              : null,
                        ),
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

  Widget _premiumMainNavItem({
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isDark = widget.isDark;
    final fg = selected ? BondhuTokens.primary : (isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight);
    return ScaleTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: BondhuTokens.motionNormal,
        curve: BondhuTokens.motionEase,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? BondhuTokens.primary.withValues(alpha: isDark ? 0.16 : 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: fg),
          ],
        ),
      ),
    );
  }

  Widget _premiumFeedNavItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isDark = widget.isDark;
    final fg = selected ? BondhuTokens.primary : (isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight);
    return ScaleTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: BondhuTokens.motionNormal,
        curve: BondhuTokens.motionEase,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? BondhuTokens.primary.withValues(alpha: isDark ? 0.15 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: fg),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsModal(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          currentUser: widget.currentUser,
          isDark: widget.isDark,
          onDarkModeChanged: widget.onDarkModeChanged,
          onLogout: () async {
            await widget.onLogout();
          },
          onProfileUpdated: widget.onProfileUpdated,
          onBondhuInviteScanned: (ref) {
            Navigator.of(context).pop();
            setState(() => _index = 0);
            pushOpenChatId.value = ref;
          },
        ),
      ),
    );
  }
}

