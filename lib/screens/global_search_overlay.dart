import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';

import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/supabase_service.dart';
import '../services/chat_service.dart' show ChatItem;
import '../services/nickname_service.dart';
import '../services/hidden_chats_service.dart';

/// Full-screen global search overlay (Facebook-style). Search people via Supabase and filter chats locally.
/// Matches bondhu-v2 App.vue global search: people + chats, debounced profile search, min 2 chars.
class GlobalSearchOverlay extends StatefulWidget {
  const GlobalSearchOverlay({
    super.key,
    required this.isDark,
    required this.chatList,
    required this.currentUserEmail,
    required this.onSelectPerson,
    required this.onSelectChat,
    required this.onClose,
  });

  final bool isDark;
  final List<ChatItem> chatList;
  final String? currentUserEmail;
  final ValueChanged<ProfileDoc> onSelectPerson;
  final ValueChanged<ChatItem> onSelectChat;
  final VoidCallback onClose;

  @override
  State<GlobalSearchOverlay> createState() => _GlobalSearchOverlayState();
}

class _GlobalSearchOverlayState extends State<GlobalSearchOverlay> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<ProfileDoc> _people = [];
  bool _isSearching = false;
  Timer? _debounceTimer;
  static const _debounceMs = 300;
  static const _minChars = 2;

  List<ChatItem> get _filteredChats {
    final q = _queryController.text.trim().toLowerCase();
    if (q.isEmpty) return [];
    return widget.chatList.where((c) {
      if (HiddenChatsService.instance.isHidden(c.id)) return false;
      final name = NicknameService.instance.getDisplayName(c).toLowerCase();
      final id = (c.id).toLowerCase();
      final email = (c.email ?? '').toLowerCase();
      return name.contains(q) || id.contains(q) || email.contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    _queryController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _queryController.removeListener(_onQueryChanged);
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounceTimer?.cancel();
    final q = _queryController.text.trim();
    if (q.length < _minChars) {
      setState(() {
        _people = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: _debounceMs), () {
      _runSearch(q);
    });
  }

  Future<void> _runSearch(String q) async {
    if (q.length < _minChars) {
      if (mounted) setState(() { _people = []; _isSearching = false; });
      return;
    }
    try {
      final list = await searchProfiles(q);
      if (mounted) {
        setState(() {
          _people = list;
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _people = []; _isSearching = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF050509) : BondhuTokens.bgLight;
    final cardBg = isDark ? const Color(0xFF101015) : Colors.white;
    final border = isDark ? const Color(0x1AFFFFFF) : BondhuTokens.borderLight;
    final textPrimary = isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight;
    final textMuted = isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight;
    final filteredChats = _filteredChats;
    final hasQuery = _queryController.text.trim().length >= _minChars;
    final noResults = hasQuery && !_isSearching && _people.isEmpty && filteredChats.isEmpty;

    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.45)),
        ),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: const SizedBox.shrink(),
          ),
        ),
        Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Column(
              children: [
                // Floating search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, color: textMuted, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _queryController,
                            focusNode: _focusNode,
                            autofocus: true,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              color: textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: AppLanguageService.instance.t('global_search_placeholder'),
                              hintStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                color: textMuted,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _queryController.text.isNotEmpty
                              ? () => _queryController.clear()
                              : widget.onClose,
                          icon: Icon(
                            _queryController.text.isNotEmpty
                                ? Icons.close_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: textMuted,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  ),
                ),

                // Results + smart suggestions
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: bg.withValues(alpha: 0.96),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        if (!hasQuery)
                          _buildSmartSuggestions(
                            context,
                            textPrimary,
                            textMuted,
                            cardBg,
                            border,
                          ),

                        if (!hasQuery) const SizedBox(height: 16),

                        // Chats
                        if (filteredChats.isNotEmpty) ...[
                          _sectionLabel(
                            AppLanguageService.instance.t('global_search_chats'),
                            textMuted,
                          ),
                          ...filteredChats.map(
                            (chat) => _chatTile(chat, cardBg, border, textPrimary, textMuted),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // People
                        _sectionLabel(
                          AppLanguageService.instance.t('global_search_people'),
                          textMuted,
                        ),
                        if (_isSearching)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(BondhuTokens.primary),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    AppLanguageService.instance.t('searching'),
                                    style: GoogleFonts.plusJakartaSans(fontSize: 14, color: textMuted),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ..._people
                              .where((p) => (p.userId).toLowerCase() != (widget.currentUserEmail ?? '').toLowerCase())
                              .map((p) => _personTile(p, cardBg, border, textPrimary, textMuted)),

                        if (noResults)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Text(
                                AppLanguageService.instance.t('global_search_no_results'),
                                style: GoogleFonts.plusJakartaSans(fontSize: 14, color: textMuted),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSmartSuggestions(
    BuildContext context,
    Color textPrimary,
    Color textMuted,
    Color cardBg,
    Color border,
  ) {
    final recentChats = widget.chatList.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick search',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Start typing to find people or chats.',
          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: textMuted),
        ),
        if (recentChats.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Recent chats',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: textMuted,
            ),
          ),
          const SizedBox(height: 8),
          ...recentChats.map((c) => _chatTile(c, cardBg, border, textPrimary, textMuted)),
        ],
      ],
    );
  }

  Widget _sectionLabel(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: color,
        ),
      ),
    );
  }

  Widget _chatTile(ChatItem chat, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.onSelectChat(chat);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: widget.isDark ? const Color(0xFF27272A) : BondhuTokens.borderLight,
                backgroundImage: chat.avatar != null && chat.avatar!.isNotEmpty
                    ? NetworkImage(chat.avatar!, scale: 1.0)
                    : null,
                child: chat.avatar == null || chat.avatar!.isEmpty
                    ? Icon(Icons.person_rounded, color: textMuted, size: 24)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (chat.email != null && chat.email!.isNotEmpty)
                      Text(
                        chat.email!,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

  Widget _personTile(ProfileDoc p, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    final name = p.name.isNotEmpty ? p.name : (p.userId.contains('@') ? p.userId.split('@').first : p.userId);
    final avatar = p.avatar.isNotEmpty ? p.avatar : defaultAvatar(p.userId);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelectPerson(p),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: widget.isDark ? const Color(0xFF27272A) : BondhuTokens.borderLight,
                backgroundImage: NetworkImage(avatar, scale: 1.0),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      p.userId,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                AppLanguageService.instance.t('message').toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: BondhuTokens.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
