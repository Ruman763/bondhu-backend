import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/supabase_service.dart';
import '../services/contacts_cache_service.dart';
import '../services/chat_service.dart' show ChatItem, ChatService;

/// Full-screen flow to create a new group: group name + select members from contacts.
class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({
    super.key,
    required this.currentUserEmail,
    required this.isDark,
    required this.chatService,
    required this.onCreateGroup,
  });

  final String? currentUserEmail;
  final bool isDark;
  final ChatService chatService;
  final void Function(ChatItem group) onCreateGroup;

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  List<ProfileDoc> _contacts = [];
  bool _loading = true;
  String _searchQuery = '';
  final Set<String> _selectedIds = {};

  String? get _myId => widget.currentUserEmail?.trim().toLowerCase();
  bool get _hasUser => _myId != null && _myId!.isNotEmpty;

  List<ProfileDoc> get _filteredContacts {
    if (_searchQuery.trim().isEmpty) return _contacts;
    final q = _searchQuery.trim().toLowerCase();
    return _contacts.where((p) {
      return p.name.toLowerCase().contains(q) || p.userId.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    if (!_hasUser) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final myId = _myId!;
    var hasShownCached = false;
    final cached = await ContactsCacheService.instance.read(myId);
    if (mounted && cached.isNotEmpty) {
      hasShownCached = true;
      setState(() {
        _contacts = cached;
        _loading = false;
      });
    }
    try {
      final ids = <String>{};
      // 1) Contacts from profile.contactList
      final contactIds = await getContactUserIds(myId);
      ids.addAll(contactIds.map((e) => e.trim().toLowerCase()));
      // 2) Private chats from chat list (fallback when user has chats but no explicit contacts yet)
      for (final c in widget.chatService.chats) {
        if (!c.isGlobal && !c.isGroup && (c.email != null && c.email!.isNotEmpty)) {
          ids.add(c.email!.trim().toLowerCase());
        }
      }
      if (ids.isEmpty) {
        if (mounted) {
          setState(() {
            _contacts = [];
            _loading = false;
          });
        }
        await ContactsCacheService.instance.write(myId, const []);
        return;
      }
      final profiles = await getProfilesByIds(ids.toList());
      if (mounted) {
        setState(() {
          _contacts = profiles;
          _loading = false;
        });
      }
      await ContactsCacheService.instance.write(myId, profiles);
    } catch (_) {
      if (mounted && !hasShownCached) setState(() => _loading = false);
    }
  }

  void _createGroup() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (_selectedIds.isEmpty) return;

    final groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
    final group = ChatItem(
      id: groupId,
      name: name,
      isGroup: true,
      lastMessage: AppLanguageService.instance.t('new_group_label'),
    );
    widget.chatService.addChat(group);
    widget.onCreateGroup(group);
    if (mounted) Navigator.of(context).pop();
  }

  BoxDecoration _bgDecoration(bool isDark) {
    if (isDark) return BoxDecoration(color: BondhuTokens.bgDark);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFE6F9F4),
          const Color(0xFFF4FCF9),
          Colors.white,
        ],
        stops: const [0.0, 0.4, 1.0],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final canCreate = _nameController.text.trim().isNotEmpty && _selectedIds.isNotEmpty;
    final textPrimary = isDark ? Colors.white : const Color(0xFF111827);
    final textMuted = isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight;

    return Scaffold(
      body: Container(
        decoration: _bgDecoration(isDark),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // App bar
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? BondhuTokens.surfaceDarkHover : Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppLanguageService.instance.t('new_group'),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Avatar + name like reference design
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark ? BondhuTokens.surfaceDarkHover : Colors.white,
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                      ),
                      child: Icon(Icons.photo_camera_rounded, size: 30, color: textMuted),
                    ),
                    const SizedBox(height: 18),
                    // Group name field – underline style
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: isDark ? Colors.white.withValues(alpha: 0.18) : const Color(0xFFE5E7EB),
                            width: 1,
                          ),
                        ),
                      ),
                      child: TextField(
                        controller: _nameController,
                        focusNode: _nameFocus,
                        onChanged: (_) => setState(() {}),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: AppLanguageService.instance.t('group_name_hint'),
                          hintStyle: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: textMuted,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Add a brief description',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: textMuted.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Add members header + full-width search
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLanguageService.instance.t('add_members'),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_contacts.isNotEmpty)
                      SizedBox(
                        height: 40,
                        child: TextField(
                          onChanged: (v) => setState(() => _searchQuery = v),
                          style: TextStyle(fontSize: 14, color: textPrimary),
                          decoration: InputDecoration(
                            hintText: AppLanguageService.instance.t('search_chats'),
                            hintStyle: TextStyle(fontSize: 13, color: textMuted),
                            filled: true,
                            fillColor: isDark ? BondhuTokens.surfaceDarkHover : Colors.white.withValues(alpha: 0.9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            isDense: true,
                            prefixIcon: Icon(Icons.search_rounded, size: 20, color: textMuted),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Contact list
              Expanded(
                child: _loading
                    ? _buildLoadingState(isDark)
                    : _filteredContacts.isEmpty
                        ? _buildEmptyState(isDark, textMuted)
                        : ListView.builder(
                            cacheExtent: 200,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            itemCount: _filteredContacts.length,
                            itemBuilder: (context, i) {
                              final p = _filteredContacts[i];
                              final userId = p.userId.trim().toLowerCase();
                              final selected = _selectedIds.contains(userId);
                              return _memberCard(isDark, textPrimary, textMuted, p, selected, () {
                                setState(() {
                                  if (selected) {
                                    _selectedIds.remove(userId);
                                  } else {
                                    _selectedIds.add(userId);
                                  }
                                });
                              });
                            },
                          ),
              ),
              // Create button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: canCreate ? _createGroup : null,
                    borderRadius: BorderRadius.circular(18),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: canCreate
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [BondhuTokens.primary, BondhuTokens.primaryDark],
                              )
                            : null,
                        color: canCreate ? null : (isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFE8EDEC)),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: canCreate
                            ? [
                                BoxShadow(
                                  color: BondhuTokens.primary.withValues(alpha: 0.4),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.group_add_rounded,
                              size: 24,
                              color: canCreate ? Colors.black : textMuted,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _selectedIds.isEmpty
                                  ? AppLanguageService.instance.t('create_group')
                                  : '${AppLanguageService.instance.t('create_group')} (${_selectedIds.length})',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: canCreate ? Colors.black : textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(BondhuTokens.primary),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading contacts…',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, Color textMuted) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: (isDark ? BondhuTokens.surfaceDarkHover : Colors.white).withValues(alpha: 0.9),
                shape: BoxShape.circle,
                boxShadow: isDark ? null : [BoxShadow(color: BondhuTokens.primary.withValues(alpha: 0.12), blurRadius: 24, spreadRadius: -4)],
              ),
              child: Icon(Icons.people_outline_rounded, size: 48, color: BondhuTokens.primary.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: 24),
            Text(
              _contacts.isEmpty
                  ? AppLanguageService.instance.t('no_contacts_hint')
                  : AppLanguageService.instance.t('no_matches'),
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color(0xFF374151),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberCard(bool isDark, Color textPrimary, Color textMuted, ProfileDoc p, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? BondhuTokens.surfaceDarkCard : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? BondhuTokens.primary : (isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE8EDEC)),
                width: selected ? 2 : 1,
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: selected ? BondhuTokens.primary.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.04),
                        blurRadius: selected ? 14 : 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? BondhuTokens.primary : Colors.transparent,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: BondhuTokens.primary.withValues(alpha: selected ? 0.3 : 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 26,
                    backgroundColor: BondhuTokens.primary.withValues(alpha: 0.12),
                    backgroundImage: p.avatar.isNotEmpty ? NetworkImage(p.avatar) : null,
                    child: p.avatar.isEmpty
                        ? Icon(Icons.person_rounded, color: BondhuTokens.primary, size: 28)
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (p.userId.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          p.userId,
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: selected ? BondhuTokens.primary : (isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF0F0F0)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    selected ? Icons.check_rounded : Icons.add_rounded,
                    size: 20,
                    color: selected ? Colors.black : textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
