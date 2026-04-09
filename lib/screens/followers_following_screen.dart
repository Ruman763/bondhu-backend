import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design_tokens.dart';
import '../services/supabase_service.dart';

/// Single dedicated page with 3 options: Followers, Following, Suggestions.
/// Modern design with search, pull-to-refresh, and back button. Used from feed profile.
class FollowersFollowingScreen extends StatefulWidget {
  const FollowersFollowingScreen({
    super.key,
    required this.currentUser,
    required this.profileName,
    required this.followerIds,
    required this.followingIds,
    this.initialTab = 0,
    required this.isOwner,
    required this.isDark,
    required this.onProfileUpdated,
    required this.onNavigateToProfile,
    this.onNavigateToChat,
  });

  final AuthUser currentUser;
  final String profileName;
  final List<String> followerIds;
  final List<String> followingIds;
  /// 0 = Followers, 1 = Following, 2 = Suggestions
  final int initialTab;
  final bool isOwner;
  final bool isDark;
  final ValueChanged<AuthUser> onProfileUpdated;
  final ValueChanged<String> onNavigateToProfile;
  final ValueChanged<String>? onNavigateToChat;

  @override
  State<FollowersFollowingScreen> createState() => _FollowersFollowingScreenState();
}

class _FollowersFollowingScreenState extends State<FollowersFollowingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ProfileDoc> _followersProfiles = [];
  List<ProfileDoc> _followingProfiles = [];
  List<ProfileDoc> _suggestionsProfiles = [];
  bool _loadingFollowers = true;
  bool _loadingFollowing = true;
  bool _loadingSuggestions = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _loadFollowers();
    _loadFollowing();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFollowers() async {
    setState(() => _loadingFollowers = true);
    final list = widget.followerIds.isEmpty
        ? <ProfileDoc>[]
        : await getProfilesByIds(widget.followerIds);
    if (mounted) {
      setState(() {
        _followersProfiles = list;
        _loadingFollowers = false;
      });
    }
  }

  Future<void> _loadFollowing() async {
    setState(() => _loadingFollowing = true);
    final list = widget.followingIds.isEmpty
        ? <ProfileDoc>[]
        : await getProfilesByIds(widget.followingIds);
    if (mounted) {
      setState(() {
        _followingProfiles = list;
        _loadingFollowing = false;
      });
    }
  }

  Future<void> _loadSuggestions() async {
    setState(() => _loadingSuggestions = true);
    final all = await listRecentProfiles(limit: 60);
    final myId = widget.currentUser.email ?? '';
    final following = widget.currentUser.following;
    final suggested = all
        .where((p) => p.userId != myId && !following.contains(p.userId))
        .take(30)
        .toList();
    if (mounted) {
      setState(() {
        _suggestionsProfiles = suggested;
        _loadingSuggestions = false;
      });
    }
  }

  List<ProfileDoc> _filter(List<ProfileDoc> list) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list
        .where((p) =>
            p.name.toLowerCase().contains(q) || p.userId.toLowerCase().contains(q))
        .toList();
  }

  Color get _surface => widget.isDark ? const Color(0xFF18181B) : Colors.white;
  Color get _cardBg => widget.isDark ? const Color(0xFF1F1F23) : const Color(0xFFF8FAFC);
  Color get _borderColor =>
      widget.isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0);
  Color get _textPrimary => widget.isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _textMuted =>
      widget.isDark ? BondhuTokens.textMutedDark : const Color(0xFF64748B);
  Color get _tabLabelInactive => _textMuted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: _textPrimary),
          tooltip: 'Back',
        ),
        title: Text(
          'People',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _buildSearchBar(),
              ),
              TabBar(
                controller: _tabController,
                labelColor: BondhuTokens.primary,
                unselectedLabelColor: _tabLabelInactive,
                indicatorColor: BondhuTokens.primary,
                indicatorWeight: 3,
                labelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                tabs: const [
                  Tab(text: 'Followers'),
                  Tab(text: 'Following'),
                  Tab(text: 'Suggestions'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList(
            loading: _loadingFollowers,
            profiles: _filter(_followersProfiles),
            emptyMessage: 'No followers yet',
            emptyDetail: 'When people follow you, they\'ll show up here.',
            isFollowersTab: true,
            onRefresh: _loadFollowers,
          ),
          _buildList(
            loading: _loadingFollowing,
            profiles: _filter(_followingProfiles),
            emptyMessage: 'Not following anyone',
            emptyDetail: 'Find people to follow from the feed or search.',
            isFollowersTab: false,
            onRefresh: _loadFollowing,
          ),
          _buildList(
            loading: _loadingSuggestions,
            profiles: _filter(_suggestionsProfiles),
            emptyMessage: 'No suggestions right now',
            emptyDetail: 'Check back later for people you might know.',
            isSuggestionsTab: true,
            onRefresh: _loadSuggestions,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor, width: 1),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Search by name or username',
          hintStyle: GoogleFonts.plusJakartaSans(fontSize: 14, color: _textMuted),
          prefixIcon: Icon(Icons.search_rounded, size: 22, color: _textMuted),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: Icon(Icons.clear_rounded, size: 20, color: _textMuted),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          isDense: true,
        ),
        style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _textPrimary),
      ),
    );
  }

  Widget _buildList({
    required bool loading,
    required List<ProfileDoc> profiles,
    required String emptyMessage,
    required String emptyDetail,
    bool isFollowersTab = false,
    bool isSuggestionsTab = false,
    required Future<void> Function() onRefresh,
  }) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: BondhuTokens.primary,
      backgroundColor: widget.isDark ? _cardBg : Colors.white,
      child: loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : profiles.isEmpty
              ? _searchQuery.trim().isEmpty
                  ? _buildEmptyState(emptyMessage, emptyDetail)
                  : _buildNoResultsState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: profiles.length,
                  itemBuilder: (_, i) => _buildTile(
                    profiles[i],
                    isFollowersTab: isFollowersTab,
                    isSuggestionsTab: isSuggestionsTab,
                  ),
                ),
    );
  }

  Widget _buildEmptyState(String message, String detail) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: BondhuTokens.primary
                    .withValues(alpha: widget.isDark ? 0.15 : 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_outline_rounded,
                size: 44,
                color: BondhuTokens.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: _textMuted),
          const SizedBox(height: 16),
          Text(
            'No matches for "$_searchQuery"',
            style: GoogleFonts.plusJakartaSans(fontSize: 15, color: _textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTile(
    ProfileDoc profile, {
    required bool isFollowersTab,
    required bool isSuggestionsTab,
  }) {
    final isFollowingTab = !isFollowersTab && !isSuggestionsTab;
    Widget trailing;
    if (isSuggestionsTab) {
      final isFollowing = widget.currentUser.following.contains(profile.userId);
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onNavigateToChat != null) ...[
            _actionChip(
              label: 'Message',
              isDestructive: false,
              onPressed: () {
                Navigator.of(context).pop();
                widget.onNavigateToChat?.call(profile.userId);
              },
            ),
            const SizedBox(width: 8),
          ],
          _actionChip(
            label: isFollowing ? 'Following' : 'Follow',
            isDestructive: false,
            isFollowing: isFollowing,
            onPressed: () =>
                isFollowing ? _unfollow(profile) : _follow(profile),
          ),
        ],
      );
    } else if (widget.isOwner && isFollowingTab) {
      trailing = _actionChip(
        label: 'Unfollow',
        isDestructive: true,
        onPressed: () => _unfollow(profile),
      );
    } else if (widget.isOwner && isFollowersTab) {
      trailing = _actionChip(
        label: 'Remove',
        isDestructive: true,
        onPressed: () => _removeFollower(profile),
      );
    } else {
      final isFollowing = widget.currentUser.following.contains(profile.userId);
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onNavigateToChat != null) ...[
            _actionChip(
              label: 'Message',
              isDestructive: false,
              onPressed: () {
                Navigator.of(context).pop();
                widget.onNavigateToChat?.call(profile.userId);
              },
            ),
            const SizedBox(width: 8),
          ],
          _actionChip(
            label: isFollowing ? 'Following' : 'Follow',
            isDestructive: false,
            isFollowing: isFollowing,
            onPressed: () =>
                isFollowing ? _unfollow(profile) : _follow(profile),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context).pop();
            widget.onNavigateToProfile(profile.userId);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderColor, width: 1),
            ),
            child: Row(
              children: [
                _avatar(profile),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        profile.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.userId,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: _textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(ProfileDoc profile) {
    final avatarUrl =
        profile.avatar.isNotEmpty ? profile.avatar : null;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: BondhuTokens.primary.withValues(alpha: 0.4),
          width: 2,
        ),
      ),
      child: ClipOval(
        child: avatarUrl != null
            ? Image.network(
                avatarUrl,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                cacheWidth: 104,
                cacheHeight: 104,
                errorBuilder: (_, Object error, StackTrace? stackTrace) =>
                    _avatarPlaceholder(profile.name),
              )
            : _avatarPlaceholder(profile.name),
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
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textMuted,
          ),
        ),
      ),
    );
  }

  Widget _actionChip({
    required String label,
    required bool isDestructive,
    required VoidCallback onPressed,
    bool isFollowing = false,
  }) {
    final bg = isDestructive
        ? (widget.isDark
            ? Colors.red.withValues(alpha: 0.2)
            : Colors.red.withValues(alpha: 0.08))
        : (isFollowing
            ? (widget.isDark
                ? Colors.white.withValues(alpha: 0.12)
                : const Color(0xFFE5E7EB))
            : BondhuTokens.primary
                .withValues(alpha: widget.isDark ? 0.2 : 0.12));
    final fg = isDestructive
        ? Colors.red.shade400
        : (isFollowing ? _textMuted : BondhuTokens.primary);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, fontWeight: FontWeight.w600, color: fg),
          ),
        ),
      ),
    );
  }

  Future<void> _follow(ProfileDoc profile) async {
    final myDocId = widget.currentUser.docId;
    if (myDocId == null) return;
    final theirProfile = await getProfileByUserId(profile.userId);
    if (theirProfile == null) return;
    final newMyFollowing =
        List<String>.from(widget.currentUser.following)..add(profile.userId);
    final newTheirFollowers = List<String>.from(theirProfile.followers)
      ..add(widget.currentUser.email ?? '');
    await updateProfile(theirProfile.docId, {'followers': newTheirFollowers});
    await updateProfile(myDocId, {'following': newMyFollowing});
    final updated = AuthUser(
      email: widget.currentUser.email,
      name: widget.currentUser.name,
      avatar: widget.currentUser.avatar,
      docId: widget.currentUser.docId,
      bio: widget.currentUser.bio,
      location: widget.currentUser.location,
      followers: widget.currentUser.followers,
      following: newMyFollowing,
    );
    widget.onProfileUpdated(updated);
    if (mounted) setState(() {});
  }

  Future<void> _unfollow(ProfileDoc profile) async {
    final myDocId = widget.currentUser.docId;
    if (myDocId == null) return;
    final newFollowing =
        List<String>.from(widget.currentUser.following)..remove(profile.userId);
    final theirProfile = await getProfileByUserId(profile.userId);
    if (theirProfile != null) {
      final newFollowers = List<String>.from(theirProfile.followers)
        ..remove(widget.currentUser.email ?? '');
      await updateProfile(theirProfile.docId, {'followers': newFollowers});
    }
    await updateProfile(myDocId, {'following': newFollowing});
    final updated = AuthUser(
      email: widget.currentUser.email,
      name: widget.currentUser.name,
      avatar: widget.currentUser.avatar,
      docId: widget.currentUser.docId,
      bio: widget.currentUser.bio,
      location: widget.currentUser.location,
      followers: widget.currentUser.followers,
      following: newFollowing,
    );
    widget.onProfileUpdated(updated);
    if (mounted) setState(() {});
  }

  Future<void> _removeFollower(ProfileDoc profile) async {
    final myDocId = widget.currentUser.docId;
    if (myDocId == null) return;
    final myEmail = widget.currentUser.email ?? '';
    final newFollowers =
        List<String>.from(widget.followerIds)..remove(profile.userId);
    final theirProfile = await getProfileByUserId(profile.userId);
    if (theirProfile != null) {
      final newFollowing =
          List<String>.from(theirProfile.following)..remove(myEmail);
      await updateProfile(theirProfile.docId, {'following': newFollowing});
    }
    await updateProfile(myDocId, {'followers': newFollowers});
    final updated = AuthUser(
      email: widget.currentUser.email,
      name: widget.currentUser.name,
      avatar: widget.currentUser.avatar,
      docId: widget.currentUser.docId,
      bio: widget.currentUser.bio,
      location: widget.currentUser.location,
      followers: newFollowers,
      following: widget.currentUser.following,
    );
    widget.onProfileUpdated(updated);
    if (mounted) {
      setState(() => _followersProfiles =
          _followersProfiles.where((p) => p.userId != profile.userId).toList());
    }
  }
}
