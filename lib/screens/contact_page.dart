import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/supabase_service.dart';
import '../services/chat_service.dart';
import '../services/contacts_cache_service.dart';

/// Contact page: design like reference — search bar, header (name, count, active),
/// horizontal "active" cards, alphabetical list with A–Z strip.
class ContactPage extends StatefulWidget {
  const ContactPage({
    super.key,
    required this.currentUserEmail,
    this.currentUserName,
    required this.isDark,
    required this.chatService,
    required this.onOpenChatWithUser,
    this.onBack,
  });

  final String? currentUserEmail;
  final String? currentUserName;
  final bool isDark;
  final ChatService? chatService;
  final void Function(String userId) onOpenChatWithUser;
  final VoidCallback? onBack;

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  List<ProfileDoc> _contacts = [];
  bool _contactsLoading = true;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {};
  static const int _activeCount = 8; // number of "active" cards in horizontal strip

  String? get _myId => widget.currentUserEmail?.trim().toLowerCase();
  bool get _hasUser => _myId != null && _myId!.isNotEmpty;

  List<ProfileDoc> get _filteredContacts {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _contacts;
    return _contacts.where((p) {
      return p.name.toLowerCase().contains(q) ||
          (p.userId.toLowerCase().contains(q));
    }).toList();
  }

  /// Group contacts by first letter (A–Z), sorted.
  Map<String, List<ProfileDoc>> get _groupedContacts {
    final list = List<ProfileDoc>.from(_filteredContacts)
      ..sort((a, b) => (a.name.isEmpty ? '?' : a.name.toUpperCase())
          .compareTo(b.name.isEmpty ? '?' : b.name.toUpperCase()));
    final map = <String, List<ProfileDoc>>{};
    for (final p in list) {
      final letter = p.name.isEmpty ? '?' : p.name[0].toUpperCase();
      final key = letter.runes.first >= 65 && letter.runes.first <= 90
          ? letter
          : '#';
      map.putIfAbsent(key, () => []).add(p);
    }
    final keys = map.keys.toList()..sort();
    return Map.fromEntries(keys.map((k) => MapEntry(k, map[k]!)));
  }

  List<ProfileDoc> get _activeContacts =>
      _filteredContacts.take(_activeCount).toList();

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant ContactPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUserEmail != widget.currentUserEmail ||
        oldWidget.chatService != widget.chatService) {
      _loadContacts();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    if (!_hasUser) {
      setState(() => _contactsLoading = false);
      return;
    }
    setState(() => _contactsLoading = true);
    final myId = _myId!;
    var hasShownCached = false;
    final cached = await ContactsCacheService.instance.read(myId);
    if (mounted && cached.isNotEmpty) {
      hasShownCached = true;
      setState(() {
        _contacts = cached;
        _contactsLoading = false;
      });
    }
    try {
      final ids = <String>{};
      // 1) Contacts from profile.contactList
      final contactIds = await getContactUserIds(myId);
      ids.addAll(contactIds.map((e) => e.trim().toLowerCase()));
      // 2) Private chats from chat list (so Contacts works even before explicit contacts exist)
      final svc = widget.chatService;
      if (svc != null) {
        for (final c in svc.chats) {
          if (!c.isGlobal && !c.isGroup && (c.email != null && c.email!.isNotEmpty)) {
            ids.add(c.email!.trim().toLowerCase());
          }
        }
      }
      if (ids.isEmpty) {
        setState(() {
          _contacts = [];
          _contactsLoading = false;
        });
        await ContactsCacheService.instance.write(myId, const []);
        return;
      }
      final profiles = await getProfilesByIds(ids.toList());
      if (mounted) {
        setState(() {
          _contacts = profiles;
          _contactsLoading = false;
        });
      }
      await ContactsCacheService.instance.write(myId, profiles);
    } catch (_) {
      if (mounted && !hasShownCached) setState(() => _contactsLoading = false);
    }
  }

  void _openChatWith(ProfileDoc profile) {
    final userId = profile.userId.trim().toLowerCase();
    widget.chatService?.addChat(ChatItem(
      id: userId,
      name: profile.name,
      email: profile.userId,
      avatar: profile.avatar,
    ));
    widget.onOpenChatWithUser(userId);
  }

  void _scrollToSection(String letter) {
    final key = _sectionKeys[letter];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(key!.currentContext!,
          duration: const Duration(milliseconds: 250), alignment: 0.0);
    }
  }

  BoxDecoration _bgDecoration(bool isDark) {
    if (isDark) return BoxDecoration(color: BondhuTokens.bgDark);
    return BoxDecoration(
      color: isDark ? BondhuTokens.bgDark : const Color(0xFFF4F4F5),
    );
  }

  Future<void> _showStartPrivateChatDialog(
      BuildContext context, bool isDark, Color textPrimary, Color textMuted) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          AppLanguageService.instance.t('start_private_chat_title'),
          style: GoogleFonts.plusJakartaSans(color: textPrimary, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLanguageService.instance.t('private_chat_hint'),
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: AppLanguageService.instance.t('enter_email_name'),
                hintStyle: TextStyle(color: textMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: GoogleFonts.plusJakartaSans(color: textPrimary),
              onSubmitted: (_) => _startPrivateChatFromDialog(ctx, controller.text.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              AppLanguageService.instance.t('cancel'),
              style: GoogleFonts.plusJakartaSans(color: textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton(
            onPressed: () => _startPrivateChatFromDialog(ctx, controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: BondhuTokens.primary, foregroundColor: Colors.black),
            child: Text(AppLanguageService.instance.t('start_chat')),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _startPrivateChatFromDialog(BuildContext dialogContext, String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty || !_hasUser) {
      Navigator.of(dialogContext).pop();
      return;
    }
    final myEmail = _myId!;
    final isEmail = trimmed.contains('@');
    final targetUserId = isEmail ? trimmed.toLowerCase() : 'private_${trimmed.toLowerCase()}';
    if (isEmail && targetUserId == myEmail) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLanguageService.instance.t('friend_request_own_email')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      Navigator.of(dialogContext).pop();
      return;
    }

    Navigator.of(dialogContext).pop();
    final name = isEmail ? ChatService.formatName(trimmed) : trimmed;
    final chatSvc = widget.chatService;
    if (chatSvc != null) {
      final chat = ChatService.createChatObject(targetUserId, name);
      chatSvc.addChat(chat);
    }
    addContactToProfile(myEmail, targetUserId);
    widget.onOpenChatWithUser(targetUserId);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111113);
    final textMuted = isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight;

    return Scaffold(
      body: Container(
        decoration: _bgDecoration(isDark),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(context, isDark, textPrimary, textMuted),
              Expanded(
                child: _hasUser && !_contactsLoading && _contacts.isNotEmpty
                    ? _buildContent(context, isDark, textPrimary, textMuted)
                    : _buildEmptyOrLoading(isDark, textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(
      BuildContext context, bool isDark, Color textPrimary, Color textMuted) {
    final searchBg = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE5E7EB);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () =>
                widget.onBack != null ? widget.onBack!() : Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: textPrimary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: searchBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: AppLanguageService.instance.t('search_placeholder'),
                  hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: textMuted,
                  ),
                  prefixIcon: Icon(Icons.search_rounded, size: 20, color: textMuted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showStartPrivateChatDialog(context, isDark, textPrimary, textMuted),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: BondhuTokens.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_rounded, size: 22, color: Colors.black),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.more_vert_rounded, size: 22, color: textPrimary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color textPrimary, Color textMuted) {
    final name = widget.currentUserName ?? widget.currentUserEmail?.split('@').first ?? 'User';
    final count = _filteredContacts.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '$count ${AppLanguageService.instance.t('contacts').toLowerCase()}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$count ${AppLanguageService.instance.t('active')}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: BondhuTokens.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSection(bool isDark, Color textPrimary, Color textMuted) {
    final active = _activeContacts;
    if (active.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 132,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: active.length,
        itemBuilder: (context, i) {
          final p = active[i];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _buildActiveCard(isDark, textPrimary, textMuted, p),
          );
        },
      ),
    );
  }

  Widget _buildActiveCard(
      bool isDark, Color textPrimary, Color textMuted, ProfileDoc profile) {
    final shortName = profile.name.length > 12
        ? '${profile.name.substring(0, 10)}..'
        : profile.name;
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    return SizedBox(
      width: 112,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openChatWith(profile),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE5E7EB),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: BondhuTokens.primary.withValues(alpha: 0.15),
                  backgroundImage: profile.avatar.isNotEmpty ? NetworkImage(profile.avatar) : null,
                  child: profile.avatar.isEmpty
                      ? Text(
                          _initials(profile.name),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: BondhuTokens.primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  shortName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _actionIcon(Icons.call_rounded, BondhuTokens.primary, 18, () => _openChatWith(profile)),
                    const SizedBox(width: 4),
                    _actionIcon(Icons.videocam_rounded, const Color(0xFF3B82F6), 18, () => _openChatWith(profile)),
                    const SizedBox(width: 4),
                    _actionIcon(Icons.chat_bubble_outline_rounded, const Color(0xFF3B82F6), 18, () => _openChatWith(profile)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionIcon(IconData icon, Color color, double size, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }

  String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.length >= 2 ? name.substring(0, 2).toUpperCase() : name[0].toUpperCase();
  }

  Widget _buildContent(
      BuildContext context, bool isDark, Color textPrimary, Color textMuted) {
    final grouped = _groupedContacts;
    if (grouped.isEmpty) {
      return _buildEmptyState(
        isDark: isDark,
        icon: Icons.search_off_rounded,
        title: AppLanguageService.instance.t('no_matches'),
        subtitle: null,
      );
    }

    return Stack(
      children: [
        ListView(
          controller: _listScrollController,
          padding: EdgeInsets.only(left: 20, right: 20 + 24, bottom: 24),
          children: [
            _buildHeader(isDark, textPrimary, textMuted),
            _buildActiveSection(isDark, textPrimary, textMuted),
            const SizedBox(height: 20),
            ...grouped.entries.expand((e) {
              final letter = e.key;
              _sectionKeys[letter] ??= GlobalKey();
              return [
                _sectionHeader(letter, isDark, textMuted),
                ...e.value.map((p) => _contactRow(isDark, textPrimary, textMuted, p)),
              ];
            }),
          ],
        ),
        Positioned(
          right: 4,
          top: 0,
          bottom: 0,
          child: _buildAlphabetStrip(isDark, grouped.keys.toList()),
        ),
      ],
    );
  }

  Widget _sectionHeader(String letter, bool isDark, Color textMuted) {
    return Container(
      key: _sectionKeys[letter],
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        letter,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: textMuted,
        ),
      ),
    );
  }

  Widget _contactRow(
      bool isDark, Color textPrimary, Color textMuted, ProfileDoc profile) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openChatWith(profile),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _avatarColor(profile.name),
                backgroundImage: profile.avatar.isNotEmpty ? NetworkImage(profile.avatar) : null,
                child: profile.avatar.isEmpty
                    ? Text(
                        _initials(profile.name),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  profile.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _actionIcon(Icons.call_rounded, BondhuTokens.primary, 16, () => _openChatWith(profile)),
              const SizedBox(width: 6),
              _actionIcon(Icons.videocam_rounded, const Color(0xFF3B82F6), 16, () => _openChatWith(profile)),
              const SizedBox(width: 6),
              _actionIcon(Icons.chat_bubble_outline_rounded, const Color(0xFF3B82F6), 16, () => _openChatWith(profile)),
            ],
          ),
        ),
      ),
    );
  }

  Color _avatarColor(String name) {
    final i = name.isEmpty ? 0 : name.runes.fold(0, (a, b) => a + b);
    const colors = [
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
      Color(0xFFA855F7),
      Color(0xFFD946EF),
      Color(0xFFEC4899),
      Color(0xFFF43F5E),
      Color(0xFFE11D48),
      Color(0xFFEA580C),
      Color(0xFFCA8A04),
      Color(0xFF65A30D),
    ];
    return colors[i % colors.length];
  }

  Widget _buildAlphabetStrip(bool isDark, List<String> letters) {
    if (letters.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: letters.map((letter) {
            return GestureDetector(
              onTap: () => _scrollToSection(letter),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  letter,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyOrLoading(bool isDark, Color textMuted) {
    if (!_hasUser) {
      return _buildEmptyState(
        isDark: isDark,
        icon: Icons.mail_outline_rounded,
        title: AppLanguageService.instance.t('enter_your_email'),
        subtitle: null,
      );
    }
    if (_contactsLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(BondhuTokens.primary),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Loading…',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: textMuted,
              ),
            ),
          ],
        ),
      );
    }
    return _buildEmptyState(
      isDark: isDark,
      icon: Icons.people_rounded,
      title: AppLanguageService.instance.t('no_contacts'),
      subtitle: AppLanguageService.instance.t('no_contacts_hint'),
    );
  }

  Widget _buildEmptyState({
    required bool isDark,
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    final textMuted = isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: (isDark ? BondhuTokens.surfaceDarkHover : Colors.white).withValues(alpha: 0.9),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: BondhuTokens.primary.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF111827),
              ),
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(fontSize: 14, color: textMuted, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
