import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/supabase_service.dart';
import '../services/chat_service.dart';
import '../services/chat_theme_service.dart';
import '../services/custom_call_message_service.dart';
import '../services/nickname_service.dart';
import '../services/chat_vibration_service.dart';
import '../services/chat_folder_service.dart';
import '../widgets/bondhu_app_logo.dart';

/// Dedicated full screen for chat info: modern Bondhu design with
/// profile hero, quick actions, and helpful options (search, media, pin, mute, clear, block, delete).
class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({
    super.key,
    required this.chat,
    required this.isDark,
    this.onViewProfile,
    required this.onSearchInConversation,
    this.onMuteChanged,
    this.onBlock,
    this.onUnblock,
    this.isBlocked = false,
    required this.onDeleteChat,
    this.onViewMedia,
    this.onPinChat,
    this.onClearChat,
    this.onMarkUnread,
    this.onArchive,
    this.onUnarchive,
    this.onSnooze,
    this.onFolderChanged,
  });

  /// Called when user changes which profile this contact sees (Default, Personal, Professional). Chat id = widget.chat.id.
  final ValueChanged<String?>? onFolderChanged;

  final ChatItem chat;
  final bool isDark;
  final VoidCallback? onViewProfile;
  final VoidCallback onSearchInConversation;
  /// Called whenever mute settings change. [muteMessages] / [muteCalls] are per-chat toggles.
  final void Function(bool muteMessages, bool muteCalls)? onMuteChanged;
  final VoidCallback? onBlock;
  final VoidCallback? onUnblock;
  final bool isBlocked;
  final VoidCallback onDeleteChat;
  final VoidCallback? onViewMedia;
  final ValueChanged<bool>? onPinChat;
  final VoidCallback? onClearChat;
  final VoidCallback? onMarkUnread;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;
  final void Function(Duration)? onSnooze;

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  static const List<String> _presetVideoAssets = <String>[
    'assets/videos/preset_1.mp4',
    'assets/videos/preset_2.mp4',
    'assets/videos/preset_3.mp4',
  ];

  bool _muteMessages = false;
  bool _muteCalls = false;
  bool _pinned = false;
  String _chatThemeKey = kChatThemeNone;
  late TextEditingController _nicknameController;
  bool _nicknameSaved = false;
  ChatVibrationPattern? _chatVibrationOverride;
  bool _hasVoiceMessage = false;
  bool _hasVideoMessage = false;
  bool _customMessageLoading = false;
  String? _profileFolder; // Which profile they see: null = Default, 'Personal', 'Work'
  int _focusTabIndex = 0; // 0 vibration, 1 call message, 2 profile view

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: NicknameService.instance.getNickname(widget.chat.id) ?? '');
    _syncFromChat();
    _profileFolder = widget.chat.folder;
    ChatFolderService.instance.load().then((_) {
      if (mounted) {
        setState(() {
          _profileFolder ??= ChatFolderService.instance.getFolder(widget.chat.id);
        });
      }
    });
    ChatThemeService.instance.getChatBackground(widget.chat.id).then((k) {
      if (mounted) {
        setState(() => _chatThemeKey = k);
      }
    });
    _initChatVibration();
    _loadCustomCallMessageState();
  }

  Future<void> _loadCustomCallMessageState() async {
    final voice = await CustomCallMessageService.instance.getVoiceMessageUrl(widget.chat.id);
    final video = await CustomCallMessageService.instance.getVideoMessageUrl(widget.chat.id);
    if (mounted) {
      setState(() {
        _hasVoiceMessage = (voice ?? '').trim().isNotEmpty;
        _hasVideoMessage = (video ?? '').trim().isNotEmpty;
      });
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _initChatVibration() async {
    await ChatVibrationService.instance.load();
    if (!mounted) return;
    final svc = ChatVibrationService.instance;
    setState(() {
      _chatVibrationOverride = svc.perChatPatterns.value[widget.chat.id];
    });
  }

  @override
  void didUpdateWidget(covariant ChatInfoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chat.id != widget.chat.id) {
      _syncFromChat();
    }
  }

  void _syncFromChat() {
    _muteMessages = widget.chat.muteMessages == true;
    _muteCalls = widget.chat.muteCalls == true;
    _pinned = widget.chat.pinned == true;
  }

  Color get _surface => widget.isDark ? const Color(0xFF0A0A0B) : const Color(0xFFF8F9FA);
  Color get _cardBg => widget.isDark ? const Color(0xFF161618) : Colors.white;
  Color get _borderColor => widget.isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFEEF0F2);
  Color get _textPrimary => widget.isDark ? Colors.white : const Color(0xFF111113);
  Color get _textMuted => widget.isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73);
  Color get _destructive => const Color(0xFFE53935);

  void _showComingSoon() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLanguageService.instance.t('coming_soon'), style: GoogleFonts.plusJakartaSans(fontSize: 14)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _cardBg,
      ),
    );
  }

  void _showEncryptionInfo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.lock_rounded, color: BondhuTokens.primary, size: 24),
            const SizedBox(width: 10),
            Text(
              'Encryption',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: _textPrimary),
            ),
          ],
        ),
        content: Text(
          AppLanguageService.instance.t('how_chats_secured'),
          style: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.5, color: _textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLanguageService.instance.t('done'),
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: BondhuTokens.primary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: _textPrimary),
          tooltip: 'Back',
        ),
        centerTitle: false,
        title: null,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.paddingOf(context).bottom + 32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProfileHero(),
            const SizedBox(height: 14),
            _buildQuickActionsStrip(),
            const SizedBox(height: 24),
            if (!widget.chat.isGroup && !widget.chat.isGlobal) ...[
              _buildSectionLabel('Nickname (only you see this)'),
              const SizedBox(height: 10),
              _buildNicknameCard(),
              const SizedBox(height: 24),
            ],
            _buildSectionLabel('Chat theme'),
            const SizedBox(height: 10),
            _buildThemeCard(),
            const SizedBox(height: 24),
            _buildSectionLabel('Options'),
            const SizedBox(height: 10),
            _buildOptionsCard(),
            if (!widget.chat.isGroup && !widget.chat.isGlobal) ...[
              const SizedBox(height: 24),
              _buildSectionLabel('Focus'),
              const SizedBox(height: 10),
              _buildFocusTabsInline(),
            ],
            const SizedBox(height: 24),
            _buildSectionLabel('Danger zone'),
            const SizedBox(height: 10),
            _buildDangerCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHero() {
    final chat = widget.chat;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.isDark
              ? [
                  BondhuTokens.primary.withValues(alpha: 0.12),
                  BondhuTokens.primary.withValues(alpha: 0.04),
                ]
              : [
                  BondhuTokens.primary.withValues(alpha: 0.08),
                  BondhuTokens.primary.withValues(alpha: 0.02),
                ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: BondhuTokens.primary.withValues(alpha: 0.15), width: 1),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: BondhuTokens.primary.withValues(alpha: 0.25),
                      blurRadius: 24,
                      spreadRadius: 0,
                    ),
                  ],
                ),
              ),
              chat.isGlobal
                  ? const BondhuAppLogo(size: 96, circular: false, iconScale: 0.44)
                  : _buildAvatar(chat.avatar, chat.name, size: 96),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            chat.name,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
              letterSpacing: -0.4,
            ),
            textAlign: TextAlign.center,
          ),
          if (chat.email != null && chat.email!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              chat.email!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 14, color: BondhuTokens.primary),
                const SizedBox(width: 8),
                Text(
                  AppLanguageService.instance.t('end_to_end_encrypted'),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroStatusChip(
                icon: _muteMessages ? Icons.notifications_off_rounded : Icons.notifications_active_rounded,
                label: _muteMessages ? 'Muted messages' : 'Messages on',
                active: !_muteMessages,
              ),
              _heroStatusChip(
                icon: _muteCalls ? Icons.call_end_rounded : Icons.call_rounded,
                label: _muteCalls ? 'Muted calls' : 'Calls on',
                active: !_muteCalls,
              ),
              _heroStatusChip(
                icon: _pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                label: _pinned ? 'Pinned' : 'Not pinned',
                active: _pinned,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStatusChip({
    required IconData icon,
    required String label,
    required bool active,
  }) {
    final bg = active
        ? BondhuTokens.primary.withValues(alpha: widget.isDark ? 0.18 : 0.12)
        : (widget.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04));
    final fg = active ? BondhuTokens.primary : _textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? BondhuTokens.primary.withValues(alpha: 0.35) : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsStrip() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _quickActionButton(
            icon: Icons.search_rounded,
            label: 'Search',
            onTap: () {
              Navigator.of(context).pop();
              widget.onSearchInConversation();
            },
          ),
          const SizedBox(width: 8),
          _quickActionButton(
            icon: Icons.photo_library_outlined,
            label: 'Media',
            onTap: () {
              if (widget.onViewMedia != null) {
                Navigator.of(context).pop();
                widget.onViewMedia!();
              } else {
                _showComingSoon();
              }
            },
          ),
          const SizedBox(width: 8),
          _quickActionButton(
            icon: _pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            label: _pinned ? 'Unpin' : 'Pin',
            onTap: () {
              setState(() => _pinned = !_pinned);
              widget.onPinChat?.call(_pinned);
            },
          ),
          const SizedBox(width: 8),
          _quickActionButton(
            icon: _muteMessages ? Icons.notifications_off_rounded : Icons.notifications_active_rounded,
            label: _muteMessages ? 'Unmute' : 'Mute',
            onTap: () {
              setState(() => _muteMessages = !_muteMessages);
              widget.onMuteChanged?.call(_muteMessages, _muteCalls);
            },
          ),
        ],
      ),
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: BondhuTokens.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String? url, String name, {double size = 88}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: BondhuTokens.primary.withValues(alpha: 0.5),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.isDark ? 0.3 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, Object error, StackTrace? stackTrace) => _avatarPlaceholder(name),
              )
            : _avatarPlaceholder(name),
      ),
    );
  }

  Widget _avatarPlaceholder(String name) {
    return Container(
      color: _borderColor,
      child: Center(
        child: Text(
          (name.isNotEmpty ? name[0] : '?').toUpperCase(),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: _textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildNicknameCard() {
    return _buildCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: _nicknameController,
            decoration: InputDecoration(
              hintText: 'e.g. Mom, Best friend',
              hintStyle: GoogleFonts.plusJakartaSans(color: _textMuted, fontSize: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              filled: true,
              fillColor: widget.isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _textPrimary),
            onSubmitted: (_) => _saveNickname(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () async {
                HapticFeedback.selectionClick();
                await _saveNickname();
              },
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _nicknameSaved ? Icons.check_circle_rounded : Icons.check_rounded,
                  size: 18,
                  key: ValueKey(_nicknameSaved),
                ),
              ),
              label: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _nicknameSaved ? 'Saved' : 'Save nickname',
                  key: ValueKey(_nicknameSaved),
                ),
              ),
              style: TextButton.styleFrom(foregroundColor: BondhuTokens.primary),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveNickname() async {
    await NicknameService.instance.setNickname(widget.chat.id, _nicknameController.text.trim());
    if (!mounted) return;
    setState(() => _nicknameSaved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _nicknameSaved = false);
    });
  }

  Widget _buildChatVibrationCard() {
    final svc = ChatVibrationService.instance;
    final globalPattern = svc.pattern.value;
    final effective = _chatVibrationOverride ?? globalPattern;
    final textPrimary = _textPrimary;
    final textMuted = _textMuted;

    return _buildCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Icon(Icons.vibration_rounded, size: 20, color: BondhuTokens.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLanguageService.instance.t('chat_vibration'),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _chatVibrationOverride == null
                          ? AppLanguageService.instance.t('chat_vibration_subtitle')
                          : 'This chat uses a custom pattern.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _vibrationChip(
                    label: 'Use global',
                    selected: _chatVibrationOverride == null,
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      await svc.setChatPattern(widget.chat.id, null);
                      if (mounted) {
                        setState(() => _chatVibrationOverride = null);
                      }
                    },
                  ),
                  ...ChatVibrationPattern.values.map((p) {
                    final selected = _chatVibrationOverride == p;
                    return _vibrationChip(
                      label: p.displayName,
                      selected: selected,
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        await svc.setChatPattern(widget.chat.id, p);
                        if (mounted) {
                          setState(() => _chatVibrationOverride = p);
                        }
                      },
                    );
                  }),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Effective for this chat: ${effective.displayName}',
                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        HapticFeedback.selectionClick();
                        await ChatVibrationService.instance.triggerForNewMessage(chatId: widget.chat.id);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Vibration preview played'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Test'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BondhuTokens.primary,
                        side: BorderSide(color: BondhuTokens.primary.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _chatVibrationOverride == null
                          ? null
                          : () async {
                              HapticFeedback.selectionClick();
                              await svc.setChatPattern(widget.chat.id, null);
                              if (mounted) setState(() => _chatVibrationOverride = null);
                            },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Reset'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textMuted,
                        side: BorderSide(color: _borderColor),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _vibrationChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? BondhuTokens.primary.withValues(alpha: 0.15)
                : (widget.isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? BondhuTokens.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? BondhuTokens.primary : _textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setVoiceMessage() async {
    final action = await _showVoiceMessagePicker();
    if (action == null || !mounted) return;
    setState(() => _customMessageLoading = true);
    try {
      String? path;
      if (action == 'record') {
        path = await _recordVoiceMessage();
      } else {
        path = await _pickAudioFile();
      }
      if (path == null || !mounted) {
        setState(() => _customMessageLoading = false);
        return;
      }
      final url = await uploadFile(path, filename: 'custom_voice_${widget.chat.id}_${DateTime.now().millisecondsSinceEpoch}.m4a');
      if (url != null && mounted) {
        await CustomCallMessageService.instance.setVoiceMessage(widget.chat.id, url);
        setState(() {
          _hasVoiceMessage = true;
          _customMessageLoading = false;
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Voice message set'), behavior: SnackBarBehavior.floating));
      } else {
        setState(() => _customMessageLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _customMessageLoading = false);
    }
  }

  Future<String?> _showVoiceMessagePicker() async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _textMuted.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                AppLanguageService.instance.t('custom_call_message_set_voice'),
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose how you want to add audio',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _textMuted,
                ),
              ),
              const SizedBox(height: 16),
              _voiceActionCard(
                icon: Icons.mic_rounded,
                title: 'Record voice message',
                subtitle: 'Capture a new message now',
                onTap: () => Navigator.pop(ctx, 'record'),
              ),
              const SizedBox(height: 10),
              _voiceActionCard(
                icon: Icons.audio_file_rounded,
                title: 'Pick audio file',
                subtitle: 'Use an existing recording',
                onTap: () => Navigator.pop(ctx, 'pick'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _voiceActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: widget.isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE8EDF2),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: BondhuTokens.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: BondhuTokens.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: _textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: _textMuted),
          ],
        ),
      ),
    );
  }

  Future<String?> _recordVoiceMessage() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/custom_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) return null;
    await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100), path: path);
    if (!mounted) return null;
    // ignore: use_build_context_synchronously
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(AppLanguageService.instance.t('voice_message_recording')),
        content: const Text('Tap Stop when done.'),
        actions: [
          TextButton(
            onPressed: () async {
              await recorder.stop();
              recorder.dispose();
              if (ctx.mounted) Navigator.pop(ctx, path);
            },
            child: const Text('Stop & Save'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<String?> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio, withData: false);
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (file.path != null) return file.path;
    return null;
  }

  Future<void> _setVideoMessage() async {
    final choice = await _showVideoMessagePicker();
    if (choice == null || !mounted) return;

    if (choice.startsWith('preset_')) {
      final index = int.tryParse(choice.split('_').last);
      if (index == null || index < 1 || index > _presetVideoAssets.length) return;
      await _setPresetVideoMessage(index - 1);
      return;
    }

    setState(() => _customMessageLoading = true);
    try {
      final picker = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (picker == null || !mounted) {
        setState(() => _customMessageLoading = false);
        return;
      }
      final path = picker.path;
      if (path.isEmpty) {
        setState(() => _customMessageLoading = false);
        return;
      }
      final url = await uploadFile(path, filename: 'custom_video_${widget.chat.id}_${DateTime.now().millisecondsSinceEpoch}.mp4');
      if (url != null && mounted) {
        await CustomCallMessageService.instance.setVideoMessage(widget.chat.id, url);
        if (!mounted) return;
        setState(() {
          _hasVideoMessage = true;
          _customMessageLoading = false;
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Video message set'), behavior: SnackBarBehavior.floating));
      } else {
        setState(() => _customMessageLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _customMessageLoading = false);
    }
  }

  Future<String?> _showVideoMessagePicker() async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _textMuted.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  AppLanguageService.instance.t('custom_call_message_set_video'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose a video with live preview',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _textMuted,
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () => Navigator.pop(ctx, 'custom'),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: widget.isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: BondhuTokens.primary.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: BondhuTokens.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.video_library_rounded, color: BondhuTokens.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pick custom video',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimary,
                                ),
                              ),
                              Text(
                                'Choose from your gallery',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: _textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: _textMuted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ...List.generate(_presetVideoAssets.length, (i) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: i == _presetVideoAssets.length - 1 ? 0 : 10),
                    child: _PresetVideoPreviewCard(
                      assetPath: _presetVideoAssets[i],
                      title: 'Pre-recorded video ${i + 1}',
                      isDark: widget.isDark,
                      onTap: () => Navigator.pop(ctx, 'preset_${i + 1}'),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _setPresetVideoMessage(int presetIndex) async {
    setState(() => _customMessageLoading = true);
    try {
      final assetPath = _presetVideoAssets[presetIndex];
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      if (bytes.isEmpty) {
        if (mounted) {
          setState(() => _customMessageLoading = false);
        }
        return;
      }

      final url = await uploadFileFromBytes(
        bytes,
        'custom_video_${widget.chat.id}_preset_${presetIndex + 1}_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );

      if (url != null && mounted) {
        await CustomCallMessageService.instance.setVideoMessage(widget.chat.id, url);
        if (!mounted) return;
        setState(() {
          _hasVideoMessage = true;
          _customMessageLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pre-recorded video ${presetIndex + 1} set'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (mounted) {
        setState(() => _customMessageLoading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _customMessageLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preset video not found. Add it to assets/videos first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<T?> showModalOption<T>({required BuildContext context, required String title, required List<T> options, required List<String> labels}) async {
    return showModalBottomSheet<T>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: _textPrimary)),
            ),
            ...List.generate(options.length, (i) {
              return ListTile(
                title: Text(labels[i], style: GoogleFonts.plusJakartaSans(color: _textPrimary)),
                onTap: () => Navigator.pop(ctx, options[i]),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomCallMessageCard() {
    final l10n = AppLanguageService.instance;
    return _buildCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            l10n.t('custom_call_message_hint'),
            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _textMuted, height: 1.4),
          ),
        ),
        if (_customMessageLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _setVoiceMessage,
                        icon: Icon(_hasVoiceMessage ? Icons.check_circle_rounded : Icons.mic_rounded, size: 20, color: BondhuTokens.primary),
                        label: Text(
                          l10n.t('custom_call_message_set_voice'),
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: BondhuTokens.primary),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: BondhuTokens.primary,
                          side: BorderSide(color: BondhuTokens.primary.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _setVideoMessage,
                        icon: Icon(_hasVideoMessage ? Icons.check_circle_rounded : Icons.videocam_rounded, size: 20, color: BondhuTokens.primary),
                        label: Text(
                          l10n.t('custom_call_message_set_video'),
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: BondhuTokens.primary),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: BondhuTokens.primary,
                          side: BorderSide(color: BondhuTokens.primary.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statusPill(
                      label: _hasVoiceMessage ? 'Voice set' : 'Voice not set',
                      icon: _hasVoiceMessage ? Icons.check_circle_rounded : Icons.mic_none_rounded,
                      active: _hasVoiceMessage,
                    ),
                    _statusPill(
                      label: _hasVideoMessage ? 'Video set' : 'Video not set',
                      icon: _hasVideoMessage ? Icons.check_circle_rounded : Icons.videocam_outlined,
                      active: _hasVideoMessage,
                    ),
                  ],
                ),
                if (_hasVoiceMessage || _hasVideoMessage) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_hasVoiceMessage)
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () async {
                              await CustomCallMessageService.instance.setVoiceMessage(widget.chat.id, null);
                              if (mounted) setState(() => _hasVoiceMessage = false);
                            },
                            icon: const Icon(Icons.mic_off_rounded, size: 18),
                            label: Text('Clear voice', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                          ),
                        ),
                      if (_hasVoiceMessage && _hasVideoMessage) const SizedBox(width: 8),
                      if (_hasVideoMessage)
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () async {
                              await CustomCallMessageService.instance.setVideoMessage(widget.chat.id, null);
                              if (mounted) setState(() => _hasVideoMessage = false);
                            },
                            icon: const Icon(Icons.videocam_off_rounded, size: 18),
                            label: Text('Clear video', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                          ),
                        ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await CustomCallMessageService.instance.clearAll(widget.chat.id);
                      if (mounted) {
                        setState(() {
                          _hasVoiceMessage = false;
                          _hasVideoMessage = false;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.t('custom_call_message_clear')), behavior: SnackBarBehavior.floating),
                        );
                      }
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text('Clear all', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFocusTabsInline() {
    final isDark = widget.isDark;
    final tabs = <({String title, IconData icon})>[
      (title: 'Vibration', icon: Icons.vibration_rounded),
      (title: 'Call Message', icon: Icons.phone_in_talk_rounded),
      (title: 'Profile View', icon: Icons.person_outline_rounded),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: List.generate(tabs.length, (i) {
              final t = tabs[i];
              final selected = _focusTabIndex == i;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _focusTabIndex = i);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? BondhuTokens.primary.withValues(alpha: isDark ? 0.28 : 0.16) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? BondhuTokens.primary.withValues(alpha: 0.5) : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            t.icon,
                            size: 15,
                            color: selected ? BondhuTokens.primary : _textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            t.title,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: selected ? BondhuTokens.primary : _textMuted,
                            ),
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
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _focusTabIndex == 0
              ? Container(key: const ValueKey('focus_vibration'), child: _buildChatVibrationCard())
              : _focusTabIndex == 1
                  ? Container(key: const ValueKey('focus_call_message'), child: _buildCustomCallMessageCard())
                  : Container(key: const ValueKey('focus_profile_view'), child: _buildProfileFolderCard()),
        ),
      ],
    );
  }

  Widget _buildProfileFolderCard() {
    final l10n = AppLanguageService.instance;
    final options = <MapEntry<String?, String>>[
      MapEntry(null, l10n.t('profile_audience_default')),
      MapEntry('Personal', l10n.t('profile_audience_personal')),
      MapEntry('Work', l10n.t('profile_audience_professional')),
    ];
    return _buildCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Text(
            l10n.t('show_them_my_profile_hint'),
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _textMuted, height: 1.35),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            _profileFolder == 'Personal'
                ? l10n.t('who_sees_personal')
                : _profileFolder == 'Work'
                    ? l10n.t('who_sees_professional')
                    : l10n.t('who_sees_default'),
            style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _textMuted),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(
            children: options.map((e) {
              final folderValue = e.key;
              final label = e.value;
              final isSelected = (folderValue == null && (_profileFolder == null || (_profileFolder?.isEmpty ?? true))) ||
                  (folderValue == 'Personal' && (_profileFolder == 'Personal' || _profileFolder == 'Family')) ||
                  (folderValue == 'Work' && _profileFolder == 'Work');
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onFolderChanged == null
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              setState(() => _profileFolder = folderValue);
                              widget.onFolderChanged!(folderValue);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.t('show_them_my_profile_saved')),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? BondhuTokens.primary.withValues(alpha: widget.isDark ? 0.25 : 0.15)
                              : (widget.isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF4F4F5)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? BondhuTokens.primary : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            label,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? BondhuTokens.primary : _textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _statusPill({
    required String label,
    required IconData icon,
    required bool active,
  }) {
    final bg = active
        ? BondhuTokens.primary.withValues(alpha: widget.isDark ? 0.18 : 0.12)
        : (widget.isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF4F4F5));
    final fg = active ? BondhuTokens.primary : _textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: active ? BondhuTokens.primary.withValues(alpha: 0.4) : Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: BondhuTokens.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _textMuted,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderColor, width: 1),
        boxShadow: widget.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(children: children),
    );
  }

  static const List<({String key, String label})> _themeOptions = [
    (key: kChatThemeNone, label: 'Default'),
    (key: kChatThemeFlowers, label: 'Flowers'),
    (key: kChatThemeWinter, label: 'Winter'),
    (key: kChatThemeMilkyWay, label: 'Milky Way'),
  ];

  Widget _buildThemeCard() {
    return _buildCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(
            children: [
              Icon(Icons.palette_outlined, size: 20, color: _textMuted),
              const SizedBox(width: 10),
              Text(
                'Background',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: _themeOptions.map((opt) {
              final selected = _chatThemeKey == opt.key;
              final asset = chatThemeAsset(opt.key);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        await ChatThemeService.instance.setChatBackground(widget.chat.id, opt.key);
                        if (mounted) setState(() => _chatThemeKey = opt.key);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected ? BondhuTokens.primary : _borderColor,
                            width: selected ? 2 : 1,
                          ),
                          color: selected ? BondhuTokens.primary.withValues(alpha: 0.08) : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                height: 40,
                                child: asset != null
                                    ? Image.asset(
                                        asset,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        errorBuilder: (context, error, stackTrace) => _themePlaceholder(widget.isDark),
                                      )
                                    : _themePlaceholder(widget.isDark),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              opt.label,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                color: selected ? BondhuTokens.primary : _textMuted,
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
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _themePlaceholder(bool isDark) {
    return Container(
      width: double.infinity,
      color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE5E7EB),
      child: Icon(
        Icons.chat_bubble_outline_rounded,
        size: 22,
        color: isDark ? const Color(0xFF525252) : const Color(0xFF9CA3AF),
      ),
    );
  }

  Widget _buildOptionsCard() {
    final options = <Widget>[
      _optionTile(
        icon: Icons.search_rounded,
        label: AppLanguageService.instance.t('search_in_conversation_label'),
        onTap: () {
          Navigator.of(context).pop();
          widget.onSearchInConversation();
        },
        showArrow: true,
      ),
      _divider(),
      _optionTile(
        icon: Icons.photo_library_outlined,
        label: AppLanguageService.instance.t('view_media_links'),
        onTap: () {
          if (widget.onViewMedia != null) {
            Navigator.of(context).pop();
            widget.onViewMedia!();
          } else {
            _showComingSoon();
          }
        },
        showArrow: true,
      ),
      _divider(),
      _optionTile(
        icon: Icons.push_pin_rounded,
        label: AppLanguageService.instance.t('pin_chat'),
        trailing: Text(
          _pinned ? AppLanguageService.instance.t('pinned') : AppLanguageService.instance.t('pin'),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _pinned ? BondhuTokens.primary : _textMuted,
          ),
        ),
        onTap: () {
          setState(() => _pinned = !_pinned);
          widget.onPinChat?.call(_pinned);
        },
      ),
      _divider(),
      _optionTile(
        icon: Icons.mark_email_unread_outlined,
        label: AppLanguageService.instance.t('mark_unread'),
        onTap: () {
          if (widget.onMarkUnread != null) {
            Navigator.of(context).pop();
            widget.onMarkUnread!();
          } else {
            _showComingSoon();
          }
        },
        showArrow: true,
      ),
      _divider(),
      _optionTile(
        icon: _muteMessages ? Icons.chat_bubble_outline_rounded : Icons.chat_bubble_outline_rounded,
        label: AppLanguageService.instance.t('mute_messages'),
        trailing: Switch(
          value: _muteMessages,
          onChanged: (v) {
            setState(() => _muteMessages = v);
            widget.onMuteChanged?.call(_muteMessages, _muteCalls);
          },
          activeThumbColor: BondhuTokens.primary,
        ),
        onTap: () {
          setState(() => _muteMessages = !_muteMessages);
          widget.onMuteChanged?.call(_muteMessages, _muteCalls);
        },
      ),
      _divider(),
      _optionTile(
        icon: _muteCalls ? Icons.call_end_rounded : Icons.call_rounded,
        label: AppLanguageService.instance.t('mute_calls'),
        trailing: Switch(
          value: _muteCalls,
          onChanged: (v) {
            setState(() => _muteCalls = v);
            widget.onMuteChanged?.call(_muteMessages, _muteCalls);
          },
          activeThumbColor: BondhuTokens.primary,
        ),
        onTap: () {
          setState(() => _muteCalls = !_muteCalls);
          widget.onMuteChanged?.call(_muteMessages, _muteCalls);
        },
      ),
      _divider(),
      _optionTile(
        icon: Icons.delete_sweep_rounded,
        label: AppLanguageService.instance.t('clear_chat'),
        onTap: () {
          if (widget.onClearChat != null) {
            _confirmClearChat();
          } else {
            _showComingSoon();
          }
        },
        showArrow: true,
      ),
    ];
    if (widget.onArchive != null || widget.onUnarchive != null || widget.onSnooze != null) {
      final isArchived = widget.chat.archivedAtMs != null;
      options.add(_divider());
      if (isArchived && widget.onUnarchive != null) {
        options.add(_optionTile(
          icon: Icons.inbox_outlined,
          label: AppLanguageService.instance.t('unarchive_chat'),
          onTap: () {
            Navigator.of(context).pop();
            widget.onUnarchive?.call();
          },
          showArrow: true,
        ));
      } else {
        if (widget.onArchive != null) {
          options.add(_optionTile(
            icon: Icons.archive_outlined,
            label: AppLanguageService.instance.t('archive_chat'),
            onTap: () {
              Navigator.of(context).pop();
              widget.onArchive?.call();
            },
            showArrow: true,
          ));
          options.add(_divider());
        }
        if (widget.onSnooze != null) {
          options.add(_optionTile(
            icon: Icons.schedule_rounded,
            label: 'Snooze chat',
            onTap: () {
              Navigator.of(context).pop();
              _showSnoozeOptions(context);
            },
            showArrow: true,
          ));
          options.add(_divider());
        }
      }
    }
    if (widget.onViewProfile != null) {
      options.addAll([_divider(), _optionTile(
        icon: Icons.person_outline_rounded,
        label: 'View profile',
        onTap: () {
          Navigator.of(context).pop();
          widget.onViewProfile?.call();
        },
        showArrow: true,
      )]);
    }
    options.addAll([_divider(), _optionTile(
      icon: Icons.security_rounded,
      label: 'Encryption info',
      onTap: _showEncryptionInfo,
      showArrow: true,
    )]);
    return _buildCard(children: options);
  }

  void _showSnoozeOptions(BuildContext context) {
    if (widget.onSnooze == null) return;
    final isDark = widget.isDark;
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Snooze chat',
                      style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                    style: IconButton.styleFrom(foregroundColor: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight),
                  ),
                ],
              ),
              _snoozeOption(ctx, isDark, AppLanguageService.instance.t('snooze_24h'), () {
                Navigator.pop(ctx);
                widget.onSnooze?.call(const Duration(hours: 24));
              }),
              _snoozeOption(ctx, isDark, AppLanguageService.instance.t('snooze_7d'), () {
                Navigator.pop(ctx);
                widget.onSnooze?.call(const Duration(days: 7));
              }),
              _snoozeOption(ctx, isDark, AppLanguageService.instance.t('snooze_30d'), () {
                Navigator.pop(ctx);
                widget.onSnooze?.call(const Duration(days: 30));
              }),
              _snoozeOption(ctx, isDark, 'Custom time…', () {
                Navigator.pop(ctx);
                _showCustomSnoozeDialog(context, isDark);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _snoozeOption(BuildContext ctx, bool isDark, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 22, color: BondhuTokens.primary),
              const SizedBox(width: 14),
              Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w500, color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight)),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomSnoozeDialog(BuildContext context, bool isDark) {
    if (widget.onSnooze == null) return;
    final controller = TextEditingController(text: '24');
    final textPrimary = isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight;
    final surface = isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: Text('Custom snooze', style: GoogleFonts.plusJakartaSans(color: textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Snooze for how many hours?', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
              decoration: const InputDecoration(
                hintText: '24',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLanguageService.instance.t('cancel'))),
          FilledButton(
            onPressed: () {
              final hours = int.tryParse(controller.text) ?? 24;
              Navigator.pop(ctx);
              widget.onSnooze?.call(Duration(hours: hours.clamp(1, 8760)));
            },
            child: const Text('Snooze'),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerCard() {
    final children = <Widget>[];
    if (widget.isBlocked && widget.onUnblock != null) {
      children.add(_actionTile(
        icon: Icons.block_rounded,
        label: 'Unblock',
        isDestructive: false,
        onTap: () {
          Navigator.of(context).pop();
          widget.onUnblock?.call();
        },
      ));
      children.add(_divider());
    } else if (widget.onBlock != null) {
      children.add(_actionTile(
        icon: Icons.block_rounded,
        label: AppLanguageService.instance.t('block'),
        isDestructive: true,
        onTap: _confirmBlock,
      ));
      children.add(_divider());
    }
    children.add(_actionTile(
      icon: Icons.delete_forever_rounded,
      label: AppLanguageService.instance.t('delete_chat'),
      isDestructive: true,
      onTap: _confirmDelete,
    ));
    return _buildCard(children: children);
  }

  Widget _divider() {
    return Divider(
      height: 1,
      indent: 72,
      endIndent: 18,
      color: _borderColor,
    );
  }

  Widget _optionTile({
    required IconData icon,
    required String label,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    bool showArrow = false,
  }) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: BondhuTokens.primary.withValues(alpha: widget.isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: BondhuTokens.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing
          else if (showArrow)
            Icon(Icons.chevron_right_rounded, size: 22, color: _textMuted),
        ],
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: content,
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required bool isDestructive,
    required VoidCallback onTap,
  }) {
    final color = isDestructive ? _destructive : _textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (isDestructive ? _destructive : _textMuted).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClearChat() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF161618) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear chat?',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: Text(
          'All messages in this chat will be removed. The chat will stay in your list.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: _textMuted,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: _textMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onClearChat?.call();
            },
            child: Text(
              'Clear',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: BondhuTokens.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmBlock() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF18181B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Block ${widget.chat.name}?',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: Text(
          'You will no longer receive messages from this chat. You can unblock later in Settings.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: _textMuted,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: _textMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              widget.onBlock?.call();
            },
            child: Text(
              'Block',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: _destructive,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF18181B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete chat?',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: Text(
          'This will remove the chat with ${widget.chat.name}. This action cannot be undone.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: _textMuted,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: _textMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (context.mounted) Navigator.pop(context); // leave info screen first
              widget.onDeleteChat();
            },
            child: Text(
              'Delete',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: _destructive,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetVideoPreviewCard extends StatefulWidget {
  const _PresetVideoPreviewCard({
    required this.assetPath,
    required this.title,
    required this.isDark,
    required this.onTap,
  });

  final String assetPath;
  final String title;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_PresetVideoPreviewCard> createState() => _PresetVideoPreviewCardState();
}

class _PresetVideoPreviewCardState extends State<_PresetVideoPreviewCard> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.asset(widget.assetPath);
      await c.initialize();
      await c.setVolume(0);
      await c.setLooping(true);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = widget.isDark ? Colors.white : const Color(0xFF111113);
    final textMuted = widget.isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73);
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: widget.isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE8EDF2),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 110,
                height: 70,
                child: _failed
                    ? Container(
                        color: Colors.black12,
                        alignment: Alignment.center,
                        child: Icon(Icons.videocam_off_rounded, color: textMuted),
                      )
                    : (_controller == null || !_controller!.value.isInitialized)
                        ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              VideoPlayer(_controller!),
                              Container(color: Colors.black.withValues(alpha: 0.15)),
                              const Center(
                                child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 28),
                              ),
                            ],
                          ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to select',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: textMuted),
          ],
        ),
      ),
    );
  }
}
