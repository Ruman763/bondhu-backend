import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../app_animations.dart';
import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/supabase_service.dart';
import '../services/encrypted_local_store.dart';
import 'followers_following_screen.dart';
import 'story_overlay.dart';

/// Relative time string (e.g. "2h", "5d") — matches website timeSince.
String _timeSince(String timestamp) {
  DateTime? dt;
  try {
    dt = DateTime.tryParse(timestamp);
  } catch (_) {}
  if (dt == null) return '0m';
  final sec = DateTime.now().difference(dt).inSeconds;
  if (sec < 60) return '${sec}m';
  if (sec < 3600) return '${sec ~/ 60}m';
  if (sec < 86400) return '${sec ~/ 3600}h';
  if (sec < 2592000) return '${sec ~/ 86400}d';
  if (sec < 31536000) return '${sec ~/ 2592000}mo';
  return '${sec ~/ 31536000}y';
}

/// Feed view matching the website (bondhu-v2 FeedView.vue) layout and styling.
class FeedView extends StatefulWidget {
  const FeedView({
    super.key,
    required this.currentUser,
    this.userName,
    this.userAvatarUrl,
    required this.isDark,
    this.onProfileUpdated,
    this.onNavigateToChat,
    this.onOpenNotifications,
    this.feedPillIndex,
    this.onFeedPillChanged,
    this.refreshStoriesTrigger,
  });

  final AuthUser currentUser;
  final String? userName;
  final String? userAvatarUrl;
  final bool isDark;
  /// Called when user saves profile (edit) or follow/unfollow so parent can update currentUser.
  final ValueChanged<AuthUser>? onProfileUpdated;
  /// Called when user taps Message on another profile — parent switches to Chat and opens that user.
  final ValueChanged<String?>? onNavigateToChat;
  /// Called when user taps the floating notification button — parent shows notification panel.
  final VoidCallback? onOpenNotifications;
  /// When non-null, parent (e.g. HomeShell) shows feed pills in its bottom bar; FeedView hides floating pills.
  final int? feedPillIndex;
  /// Notify parent when feed pill selection changes (e.g. navigating to profile).
  final ValueChanged<int>? onFeedPillChanged;
  /// When this value changes, stories are reloaded (e.g. after adding a story from Chat tab).
  final int? refreshStoriesTrigger;

  @override
  State<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<FeedView> with TickerProviderStateMixin {
  bool _showSearchBar = false;
  String _searchQuery = '';
  final Map<String, bool> _expandedComments = {};
  final Map<String, String> _commentInputs = {};
  // ignore: unused_field - written by listener to trigger setState
  String? _heartAnimationPostId;
  late AnimationController _heartController;
  // ignore: unused_field - kept for potential heart burst overlay
  late Animation<double> _heartScale;
  // ignore: unused_field - kept for potential heart burst overlay
  late Animation<double> _heartOpacity;

  final TextEditingController _newPostController = TextEditingController();
  String? _selectedMediaPath;
  bool _selectedMediaIsVideo = false;
  bool _isUploading = false;
  Uint8List? _pickedImageBytes;
  String _pickedImageExt = 'jpg';
  int _feedPillIndex = 0; // 0=Home, 1=Videos, 2=Profile
  int _profileViewTab = 0; // 0=grid, 1=reels, 2=saved (only when profile)
  List<StoryItem> _stories = [];
  bool _storiesLoading = true;
  List<_FeedPost> _posts = [];
  bool _postsLoading = true;
  Future<void>? _postsInFlight;
  Future<void>? _storiesInFlight;
  static const String _hiddenPostIdsKey = 'bondhu_hidden_post_ids';
  Set<String> _hiddenPostIds = {};
  /// When non-null, profile tab shows this user (from post tap or search). When null, shows current user.
  ProfileDoc? _viewingProfile;

  String? get _userAvatarUrl => widget.userAvatarUrl ?? widget.currentUser.avatar;
  String get _userName => widget.userName ?? widget.currentUser.name ?? (widget.currentUser.email ?? '').split('@').first;
  String get _userBio => widget.currentUser.bio ?? 'No bio yet.';

  /// Active profile for profile tab: viewed user or current user (website: activeProfile = viewingProfile || currentUser).
  String get _activeProfileUserId => _viewingProfile?.userId ?? (widget.currentUser.email ?? '');
  String get _activeProfileName => _viewingProfile?.name ?? _userName;
  String? get _activeProfileAvatar => _viewingProfile?.avatar ?? _userAvatarUrl;
  String get _activeProfileBio => _viewingProfile?.bio ?? _userBio;
  String? get _activeProfileLocation => _viewingProfile?.location ?? widget.currentUser.location;
  String? get _activeProfileDocId => _viewingProfile?.docId ?? widget.currentUser.docId;
  List<String> get _activeProfileFollowers => _viewingProfile?.followers ?? widget.currentUser.followers;
  List<String> get _activeProfileFollowing => _viewingProfile?.following ?? widget.currentUser.following;

  bool get _isOwner => _viewingProfile == null || _viewingProfile!.userId == (widget.currentUser.email ?? '');
  bool get _isFollowingActiveProfile =>
      !_isOwner && (widget.currentUser.following.contains(_activeProfileUserId));

  /// Effective pill index: from parent when on Feed in shell, else internal state.
  int get _effectiveFeedPillIndex => widget.feedPillIndex ?? _feedPillIndex;
  void _setFeedPillIndex(int i) {
    widget.onFeedPillChanged?.call(i);
    if (widget.onFeedPillChanged == null) setState(() => _feedPillIndex = i);
  }

  int get _profilePostsCount => _filteredPosts.where((p) => p.userId == _activeProfileUserId).length;
  int get _profileFollowersCount => _activeProfileFollowers.length;
  int get _profileFollowingCount => _activeProfileFollowing.length;

  @override
  void initState() {
    super.initState();
    _loadCachedFeedState();
    _loadPosts();
    _loadStories();
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _heartScale = Tween<double>(begin: 0.3, end: 1.2).animate(
      CurvedAnimation(parent: _heartController, curve: const ClampedCurve(Curves.elasticOut)),
    );
    _heartOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _heartController, curve: const Interval(0.4, 1, curve: Curves.easeOut)),
    );
    _heartController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _heartController.reset();
        if (mounted) setState(() => _heartAnimationPostId = null);
      }
    });
  }

  @override
  void didUpdateWidget(FeedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshStoriesTrigger != widget.refreshStoriesTrigger && widget.refreshStoriesTrigger != null) {
      _loadStories();
    }
  }

  @override
  void dispose() {
    _heartController.dispose();
    _newPostController.dispose();
    super.dispose();
  }

  Future<void> _loadStories() async {
    if (_storiesInFlight != null) return _storiesInFlight;
    final job = _loadStoriesInternal();
    _storiesInFlight = job;
    try {
      await job;
    } finally {
      _storiesInFlight = null;
    }
  }

  Future<void> _loadStoriesInternal() async {
    setState(() => _storiesLoading = true);
    try {
      final docs = await getStories();
      if (!mounted) return;
      final stories = storyDocumentsToItems(docs, widget.currentUser.email);
      setState(() {
        _stories = stories;
        _storiesLoading = false;
      });
      await _saveStoriesCache(stories);
    } catch (_) {
      if (mounted) setState(() => _storiesLoading = false);
    }
  }

  Future<void> _loadHiddenPostIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_hiddenPostIdsKey);
      if (json != null && json.isNotEmpty) {
        final list = jsonDecode(json) as List<dynamic>?;
        if (list != null) _hiddenPostIds = list.map((e) => e.toString()).toSet();
      }
    } catch (_) {}
  }

  Future<void> _addHiddenPostId(String id) async {
    _hiddenPostIds.add(id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_hiddenPostIdsKey, jsonEncode(_hiddenPostIds.toList()));
    } catch (_) {}
  }

  /// Load posts from Supabase and map to _FeedPost with profile avatars/names (website: fetchPosts + formatPost).
  Future<void> _loadPosts() async {
    if (_postsInFlight != null) return _postsInFlight;
    final job = _loadPostsInternal();
    _postsInFlight = job;
    try {
      await job;
    } finally {
      _postsInFlight = null;
    }
  }

  Future<void> _loadPostsInternal() async {
    if (!mounted) return;
    setState(() => _postsLoading = true);
    try {
      await _loadHiddenPostIds();
      final docs = await getPosts(limit: 50, offset: 0);
      if (!mounted) return;
      final postDocs = docs.map((d) => PostDoc.fromDoc(d)).toList();
      final userIds = postDocs.map((p) => p.userId).where((s) => s.isNotEmpty).toSet().toList();
      final profiles = userIds.isEmpty ? <ProfileDoc>[] : await getProfilesByIds(userIds);
      final profileMap = { for (final p in profiles) p.userId: p };
      final allPosts = postDocs.map((p) => _postDocToFeedPost(p, profileMap)).toList();
      final posts = allPosts.where((p) => !_hiddenPostIds.contains(p.id)).toList();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _postsLoading = false;
      });
      await _savePostsCache(posts);
    } catch (e) {
      if (mounted) {
        setState(() => _postsLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLanguageService.instance.t('could_not_load_feed')}: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  _FeedPost _postDocToFeedPost(PostDoc p, Map<String, ProfileDoc> profileMap) {
    final profile = profileMap[p.userId];
    final comments = p.comments.map((c) {
      return _FeedComment(
        id: c['id']?.toString() ?? '',
        name: c['name']?.toString() ?? 'Unknown',
        avatar: c['avatar']?.toString() ?? defaultAvatar(c['userId']?.toString()),
        text: c['text']?.toString() ?? '',
      );
    }).toList();
    return _FeedPost(
      id: p.docId,
      userName: profile?.name ?? (p.userId.contains('@') ? p.userId.split('@').first : p.userId),
      userId: p.userId,
      avatar: profile?.avatar ?? defaultAvatar(p.userId),
      timeAgo: _timeSince(p.timestamp),
      content: p.content,
      mediaUrl: p.mediaUrl ?? '',
      type: p.type,
      likesList: List<String>.from(p.likesList),
      savedBy: List<String>.from(p.savedBy),
      comments: comments,
    );
  }

  String _normAccount() => (widget.currentUser.email ?? '').trim().toLowerCase();
  String get _postsCacheKey => 'feed_posts_cache_${_normAccount()}';
  String get _storiesCacheKey => 'feed_stories_cache_${_normAccount()}';

  Future<void> _loadCachedFeedState() async {
    if (!EncryptedLocalStore.instance.isReady) return;
    try {
      final rawPosts = await EncryptedLocalStore.instance.getString(_postsCacheKey);
      if (rawPosts != null && rawPosts.isNotEmpty) {
        final decoded = jsonDecode(rawPosts) as List<dynamic>?;
        if (decoded != null && decoded.isNotEmpty) {
          final posts = decoded
              .whereType<Map>()
              .map((m) => _feedPostFromCache(Map<String, dynamic>.from(m)))
              .toList();
          if (mounted) {
            setState(() {
              _posts = posts;
              _postsLoading = false;
            });
          }
        }
      }
      final rawStories = await EncryptedLocalStore.instance.getString(_storiesCacheKey);
      if (rawStories != null && rawStories.isNotEmpty) {
        final decoded = jsonDecode(rawStories) as List<dynamic>?;
        if (decoded != null && decoded.isNotEmpty) {
          final stories = decoded
              .whereType<Map>()
              .map((m) => _storyFromCache(Map<String, dynamic>.from(m)))
              .toList();
          if (mounted) {
            setState(() {
              _stories = stories;
              _storiesLoading = false;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _savePostsCache(List<_FeedPost> posts) async {
    if (!EncryptedLocalStore.instance.isReady) return;
    try {
      final data = posts.map((p) => _feedPostToCache(p)).toList();
      await EncryptedLocalStore.instance.setString(_postsCacheKey, jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _saveStoriesCache(List<StoryItem> stories) async {
    if (!EncryptedLocalStore.instance.isReady) return;
    try {
      final data = stories.map((s) => _storyToCache(s)).toList();
      await EncryptedLocalStore.instance.setString(_storiesCacheKey, jsonEncode(data));
    } catch (_) {}
  }

  Map<String, dynamic> _feedPostToCache(_FeedPost p) => {
        'id': p.id,
        'userName': p.userName,
        'userId': p.userId,
        'avatar': p.avatar,
        'timeAgo': p.timeAgo,
        'content': p.content,
        'mediaUrl': p.mediaUrl,
        'type': p.type,
        'likesList': p.likesList,
        'savedBy': p.savedBy,
        'comments': p.comments.map((c) => c.toMap()).toList(),
      };

  _FeedPost _feedPostFromCache(Map<String, dynamic> m) {
    final commentsRaw = (m['comments'] as List?) ?? const [];
    final comments = commentsRaw.whereType<Map>().map((c) {
      final cm = Map<String, dynamic>.from(c);
      return _FeedComment(
        id: cm['id']?.toString() ?? '',
        name: cm['name']?.toString() ?? 'Unknown',
        avatar: cm['avatar']?.toString() ?? '',
        text: cm['text']?.toString() ?? '',
      );
    }).toList();
    return _FeedPost(
      id: m['id']?.toString() ?? '',
      userName: m['userName']?.toString() ?? 'User',
      userId: m['userId']?.toString() ?? '',
      avatar: m['avatar']?.toString() ?? '',
      timeAgo: m['timeAgo']?.toString() ?? '0m',
      content: m['content']?.toString() ?? '',
      mediaUrl: m['mediaUrl']?.toString() ?? '',
      type: m['type']?.toString() ?? 'text',
      likesList: ((m['likesList'] as List?) ?? const []).map((e) => e.toString()).toList(),
      savedBy: ((m['savedBy'] as List?) ?? const []).map((e) => e.toString()).toList(),
      comments: comments,
    );
  }

  Map<String, dynamic> _storyToCache(StoryItem s) => {
        'id': s.id,
        'userId': s.userId,
        'userName': s.userName,
        'avatar': s.avatar,
        'mediaUrl': s.mediaUrl,
        'time': s.time,
        'timestamp': s.timestamp,
        'likes': s.likes,
        'views': s.views,
        'comments': s.comments,
      };

  StoryItem _storyFromCache(Map<String, dynamic> m) => StoryItem(
        id: m['id']?.toString() ?? '',
        userId: m['userId']?.toString() ?? '',
        userName: m['userName']?.toString() ?? 'User',
        avatar: m['avatar']?.toString() ?? '',
        mediaUrl: m['mediaUrl']?.toString() ?? '',
        time: m['time']?.toString() ?? '',
        timestamp: m['timestamp'] is int ? m['timestamp'] as int : int.tryParse(m['timestamp']?.toString() ?? '') ?? 0,
        likes: ((m['likes'] as List?) ?? const []).map((e) => e.toString()).toList(),
        views: ((m['views'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        comments: ((m['comments'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );

  Future<void> _pickAndUploadStory() async {
    try {
      final picker = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picker == null || !mounted) return;
      String? url;
      if (kIsWeb) {
        final bytes = await picker.readAsBytes();
        if (!mounted) return;
        final ext = picker.name.split('.').last;
        url = await uploadFileFromBytes(bytes, 'story_${DateTime.now().millisecondsSinceEpoch}.${ext.isEmpty ? "jpg" : ext}');
      } else {
        url = await uploadFile(picker.path);
      }
      if (!mounted || url == null || url.isEmpty) return;
      final email = widget.currentUser.email ?? '';
      if (email.isEmpty) return;
      await createStory(userId: email, mediaUrl: url);
      if (mounted) _loadStories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLanguageService.instance.t('failed_add_story')}: $e'), behavior: SnackBarBehavior.floating),
        );
      }
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
        currentUserName: _userName,
        currentUserAvatar: _userAvatarUrl,
        isDark: widget.isDark,
        onClose: () => Navigator.of(ctx).pop(),
        onStoriesUpdated: _loadStories,
      ),
    );
  }

  /// Navigate to profile: own profile clears _viewingProfile; other user fetches profile and sets _viewingProfile, switches to profile tab.
  Future<void> _navigateToProfile(String userId) async {
    final myEmail = widget.currentUser.email ?? '';
    if (userId == myEmail) {
      setState(() => _viewingProfile = null);
      _setFeedPillIndex(2);
      return;
    }
    final profile = await getProfileByUserId(userId);
    if (!mounted) return;
    setState(() => _viewingProfile = profile);
    _setFeedPillIndex(2);
  }

  Future<void> _showEditProfileSheet(BuildContext context, bool isDark) async {
    final nameController = TextEditingController(text: widget.currentUser.name ?? '');
    final bioController = TextEditingController(text: widget.currentUser.bio ?? '');
    final locationController = TextEditingController(text: widget.currentUser.location ?? '');
    String? newAvatarUrl = widget.currentUser.avatar;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280,
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(AppLanguageService.instance.t('edit_profile'), style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight)),
                  const SizedBox(height: 12),
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                        if (x == null || !ctx.mounted) return;
                        final bytes = await x.readAsBytes();
                        final ext = x.path.split('.').last;
                        final url = await uploadFileFromBytes(bytes, 'avatar.$ext');
                        if (url != null && ctx.mounted) {
                          newAvatarUrl = url;
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(AppLanguageService.instance.t('photo_selected')), behavior: SnackBarBehavior.floating));
                        }
                      },
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 44,
                            backgroundColor: isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.borderLight,
                            backgroundImage: (newAvatarUrl != null && newAvatarUrl!.isNotEmpty)
                                ? NetworkImage(newAvatarUrl!, scale: 1.0)
                                : null,
                            child: (newAvatarUrl == null || newAvatarUrl!.isEmpty) ? Icon(Icons.person, size: 44, color: BondhuTokens.textMutedDark) : null,
                          ),
                          const SizedBox(height: 6),
                          Text(AppLanguageService.instance.t('tap_change_photo'), style: GoogleFonts.plusJakartaSans(fontSize: 11, color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Name',
                  filled: true,
                  fillColor: isDark ? BondhuTokens.inputBgDark : BondhuTokens.inputBgLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                style: TextStyle(color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bioController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Bio',
                  filled: true,
                  fillColor: isDark ? BondhuTokens.inputBgDark : BondhuTokens.inputBgLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                style: TextStyle(color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationController,
                decoration: InputDecoration(
                  labelText: 'Location',
                  filled: true,
                  fillColor: isDark ? BondhuTokens.inputBgDark : BondhuTokens.inputBgLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                style: TextStyle(color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                        side: BorderSide(color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight),
                      ),
                      child: Text(AppLanguageService.instance.t('cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        final bio = bioController.text.trim();
                        final location = locationController.text.trim();
                        Navigator.of(ctx).pop();
                        final u = widget.currentUser;
                        final profile = await syncProfile(u);
                        if (profile == null || !mounted) return;
                        await updateProfile(profile.docId, {
                          'name': name.isNotEmpty ? name : (u.email ?? '').split('@').first,
                          'bio': bio,
                          'location': location.isNotEmpty ? location : null,
                          ...? (newAvatarUrl != null ? {'avatar': newAvatarUrl} : null),
                        });
                        final updated = AuthUser(
                          email: u.email,
                          name: name.isNotEmpty ? name : u.name,
                          avatar: newAvatarUrl ?? u.avatar,
                          docId: profile.docId,
                          bio: bio.isEmpty ? null : bio,
                          location: location.isEmpty ? null : location,
                          followers: u.followers,
                          following: u.following,
                        );
                        await storeUser(updated);
                        widget.onProfileUpdated?.call(updated);
                        if (mounted) setState(() {});
                      },
                      style: FilledButton.styleFrom(backgroundColor: BondhuTokens.primary, foregroundColor: Colors.black),
                      child: Text(AppLanguageService.instance.t('save_changes')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    ),
    );
    nameController.dispose();
    bioController.dispose();
    locationController.dispose();
  }

  Future<void> _toggleFollow() async {
    if (_isOwner) return;
    final myEmail = widget.currentUser.email ?? '';
    if (myEmail.isEmpty) return;

    // Resolve our profile docId (currentUser.docId is often null until profile is synced)
    String? myDocId = widget.currentUser.docId;
    if (myDocId == null) {
      var myProfile = await getProfileByUserId(myEmail);
      // If we have no profile yet, sync creates one and returns it
      if (myProfile == null) {
        myProfile = await syncProfile(widget.currentUser);
        if (myProfile != null && mounted) {
          widget.onProfileUpdated?.call(AuthUser(
            email: widget.currentUser.email,
            name: widget.currentUser.name,
            avatar: widget.currentUser.avatar,
            docId: myProfile.docId,
            bio: widget.currentUser.bio,
            location: widget.currentUser.location,
            followers: widget.currentUser.followers,
            following: widget.currentUser.following,
          ));
        }
      }
      myDocId = myProfile?.docId;
      if (myDocId == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageService.instance.t('could_not_follow_try_again'))),
        );
        return;
      }
    }

    final theirDocId = _activeProfileDocId;
    if (theirDocId == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLanguageService.instance.t('could_not_follow_try_again'))),
      );
      return;
    }

    final theirId = _activeProfileUserId;
    List<String> newMyFollowing = List.from(widget.currentUser.following);
    List<String> newTheirFollowers = List.from(_activeProfileFollowers);
    if (_isFollowingActiveProfile) {
      newMyFollowing.remove(theirId);
      newTheirFollowers.remove(myEmail);
    } else {
      if (!newMyFollowing.contains(theirId)) newMyFollowing.add(theirId);
      if (!newTheirFollowers.contains(myEmail)) newTheirFollowers.add(myEmail);
    }

    // If a follow Cloud Function is configured, use it (updates both profiles with server permissions)
    final viaFunction = await followUnfollowViaFunction(myEmail, theirId, !_isFollowingActiveProfile);
    if (viaFunction) {
      final updatedUser = AuthUser(
        email: widget.currentUser.email,
        name: widget.currentUser.name,
        avatar: widget.currentUser.avatar,
        docId: myDocId,
        bio: widget.currentUser.bio,
        location: widget.currentUser.location,
        followers: widget.currentUser.followers,
        following: newMyFollowing,
      );
      widget.onProfileUpdated?.call(updatedUser);
      if (_viewingProfile != null) {
        setState(() {
          _viewingProfile = ProfileDoc(
            docId: _viewingProfile!.docId,
            userId: _viewingProfile!.userId,
            name: _viewingProfile!.name,
            avatar: _viewingProfile!.avatar,
            bio: _viewingProfile!.bio,
            location: _viewingProfile!.location,
            followers: newTheirFollowers,
            following: _viewingProfile!.following,
          );
        });
      } else {
        setState(() {});
      }
      return;
    }

    // Update our profile first (we always have permission to our own document)
    try {
      await updateProfile(myDocId!, {'following': newMyFollowing});
    } catch (e) {
      if (kDebugMode) debugPrint('[Feed] Follow: update own profile failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageService.instance.t('could_not_follow_try_again'))),
        );
      }
      return;
    }

    // Update their profile (may fail with 403 if collection only allows owner write)
    bool theirProfileUpdated = false;
    try {
      await updateProfile(theirDocId!, {'followers': newTheirFollowers});
      theirProfileUpdated = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Feed] Follow: update their profile failed (permission?): $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLanguageService.instance.t('following_their_count_may_not_update')),
          ),
        );
      }
    }

    // Pass back docId so shell's currentUser has it for next time
    final updatedUser = AuthUser(
      email: widget.currentUser.email,
      name: widget.currentUser.name,
      avatar: widget.currentUser.avatar,
      docId: myDocId,
      bio: widget.currentUser.bio,
      location: widget.currentUser.location,
      followers: widget.currentUser.followers,
      following: newMyFollowing,
    );
    widget.onProfileUpdated?.call(updatedUser);
    if (_viewingProfile != null) {
      setState(() {
        _viewingProfile = ProfileDoc(
          docId: _viewingProfile!.docId,
          userId: _viewingProfile!.userId,
          name: _viewingProfile!.name,
          avatar: _viewingProfile!.avatar,
          bio: _viewingProfile!.bio,
          location: _viewingProfile!.location,
          followers: theirProfileUpdated ? newTheirFollowers : _viewingProfile!.followers,
          following: _viewingProfile!.following,
        );
      });
    } else {
      setState(() {});
    }
  }

  void _showFollowersFollowingSheet(BuildContext context, bool isDark, bool showFollowers) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FollowersFollowingScreen(
          currentUser: widget.currentUser,
          profileName: _activeProfileName,
          followerIds: _activeProfileFollowers,
          followingIds: _activeProfileFollowing,
          initialTab: showFollowers ? 0 : 1,
          isOwner: _isOwner,
          isDark: isDark,
          onProfileUpdated: (updated) => widget.onProfileUpdated?.call(updated),
          onNavigateToProfile: (userId) => _navigateToProfile(userId),
          onNavigateToChat: widget.onNavigateToChat != null
              ? (userId) => widget.onNavigateToChat?.call(userId)
              : null,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _showPostDetail(BuildContext context, _FeedPost post, bool isDark) {
    final isOwner = post.userId == (widget.currentUser.email ?? '');
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              post.userName,
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            actions: [
              if (isOwner)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                  onSelected: (value) async {
                    if (value == 'edit') {
                      await _editPost(post);
                    } else if (value == 'delete') {
                      await _deletePost(post);
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('Edit caption'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete post'),
                    ),
                  ],
                ),
            ],
          ),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Center(
                    child: post.type == 'video'
                        ? _FeedVideoPlayer(url: post.mediaUrl)
                        : InteractiveViewer(
                            minScale: 1,
                            maxScale: 4,
                            child: _premiumNetworkImage(
                              post.mediaUrl,
                              fit: BoxFit.contain,
                              error: const Icon(Icons.image_not_supported, color: Colors.white70, size: 42),
                            ),
                          ),
                  ),
                ),
                if (post.content.trim().isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                    color: Colors.black.withValues(alpha: 0.7),
                    child: Text(
                      post.content,
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white, height: 1.4),
                    ),
                  ),
              ],
            ),
          ),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _editPost(_FeedPost post) async {
    final controller = TextEditingController(text: post.content);
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit caption', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Write a caption'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLanguageService.instance.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final text = (newText ?? '').trim();
    if (text.isEmpty || text == post.content) return;

    setState(() {
      _posts = _posts.map((p) => p.id == post.id ? p.copyWith(content: text) : p).toList();
    });
    try {
      await updatePost(post.id, {'content': text});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post updated'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _posts = _posts.map((p) => p.id == post.id ? p.copyWith(content: post.content) : p).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update post: $e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _showPostMoreSheet(BuildContext context, _FeedPost post, bool isDark) {
    final isOwner = post.userId == (widget.currentUser.email ?? '');
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOwner)
              _postMoreTile(ctx, isDark, Icons.edit_outlined, 'Edit caption', () {
                Navigator.pop(ctx);
                _editPost(post);
              }),
            if (isOwner)
              _postMoreTile(ctx, isDark, Icons.delete_outline, 'Delete post', () {
                Navigator.pop(ctx);
                _deletePost(post);
              }, isDestructive: true),
            _postMoreTile(ctx, isDark, Icons.link, 'Copy link', () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLanguageService.instance.t('link_copied')), behavior: SnackBarBehavior.floating));
            }),
            _postMoreTile(ctx, isDark, Icons.flag_outlined, 'Report', () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLanguageService.instance.t('report_submitted')), behavior: SnackBarBehavior.floating),
              );
            }),
            _postMoreTile(ctx, isDark, Icons.visibility_off_outlined, 'Not interested', () {
              Navigator.pop(ctx);
              _addHiddenPostId(post.id);
              setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Post hidden from feed'), behavior: SnackBarBehavior.floating),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _postMoreTile(BuildContext context, bool isDark, IconData icon, String label, VoidCallback onTap, {bool isDestructive = false}) {
    final color = isDestructive ? Colors.red : (isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight);
    final textColor = isDestructive ? Colors.red : (isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight);
    return ListTile(
      leading: Icon(icon, size: 22, color: isDestructive ? Colors.red : color),
      title: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 14, color: textColor, fontWeight: isDestructive ? FontWeight.w600 : null)),
      onTap: onTap,
    );
  }

  List<_FeedComment> _allCommentsFor(_FeedPost post) => post.comments;

  Future<void> _submitComment(_FeedPost post) async {
    final text = (_commentInputs[post.id] ?? '').trim();
    if (text.isEmpty) return;
    final myEmail = widget.currentUser.email ?? '';
    if (myEmail.isEmpty) return;
    final newComment = _FeedComment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _userName,
      avatar: _userAvatarUrl ?? defaultAvatar(myEmail),
      text: text,
    );
    final updatedComments = [...post.comments, newComment];
    setState(() {
      _posts = _posts.map((p) => p.id == post.id ? p.copyWith(comments: updatedComments) : p).toList();
      _commentInputs[post.id] = '';
    });
    try {
      await updatePost(post.id, {
        'comments': updatedComments.map((c) => c.toMap()).toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageService.instance.t('comment_posted')), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _posts = _posts.map((p) => p.id == post.id ? p.copyWith(comments: post.comments) : p).toList();
          _commentInputs[post.id] = text;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLanguageService.instance.t('could_not_post_comment')}: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _clearPostInput() {
    _newPostController.clear();
    setState(() {
      _selectedMediaPath = null;
      _pickedImageBytes = null;
    });
  }

  Future<void> _toggleLike(_FeedPost post) async {
    final myEmail = widget.currentUser.email ?? '';
    if (myEmail.isEmpty) return;
    final isLiked = post.likesList.contains(myEmail);
    final newList = isLiked
        ? post.likesList.where((e) => e != myEmail).toList()
        : [...post.likesList, myEmail];
    setState(() {
      _posts = _posts.map((p) => p.id == post.id ? p.copyWith(likesList: newList) : p).toList();
    });
    try {
      await updatePost(post.id, {'likesList': newList});
    } catch (e) {
      if (mounted) {
        setState(() {
          _posts = _posts.map((p) => p.id == post.id ? p.copyWith(likesList: post.likesList) : p).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLanguageService.instance.t('could_not_update_like')}: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _toggleSave(_FeedPost post) async {
    final myEmail = widget.currentUser.email ?? '';
    if (myEmail.isEmpty) return;
    final isSaved = post.savedBy.contains(myEmail);
    final newList = isSaved
        ? post.savedBy.where((e) => e != myEmail).toList()
        : [...post.savedBy, myEmail];
    setState(() {
      _posts = _posts.map((p) => p.id == post.id ? p.copyWith(savedBy: newList) : p).toList();
    });
    try {
      await updatePost(post.id, {'savedBy': newList});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isSaved ? 'Removed from saved' : 'Saved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _posts = _posts.map((p) => p.id == post.id ? p.copyWith(savedBy: post.savedBy) : p).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLanguageService.instance.t('could_not_update_save')}: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _deletePost(_FeedPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLanguageService.instance.t('delete_post')),
        content: Text(AppLanguageService.instance.t('cannot_undo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLanguageService.instance.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppLanguageService.instance.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = post.id;
    setState(() => _posts = _posts.where((p) => p.id != id).toList());
    final ok = await deletePost(id);
    if (mounted) {
      if (!ok) {
        setState(() => _posts = [..._posts, post]);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageService.instance.t('failed_delete_post')), behavior: SnackBarBehavior.floating),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageService.instance.t('post_deleted')), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _pickImageForPost() async {
    try {
      final picker = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picker == null || !mounted) return;
      if (kIsWeb) {
        final bytes = await picker.readAsBytes();
        if (!mounted) return;
        setState(() {
          _pickedImageBytes = bytes;
          _pickedImageExt = picker.name.split('.').last;
          if (_pickedImageExt.isEmpty) _pickedImageExt = 'jpg';
          _selectedMediaPath = 'picked';
          _selectedMediaIsVideo = false;
        });
      } else {
        setState(() {
          _selectedMediaPath = picker.path;
          _selectedMediaIsVideo = false;
          _pickedImageBytes = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLanguageService.instance.t('failed_pick_image')}: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _pickVideoForPost() async {
    try {
      final picker = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (picker == null || !mounted) return;
      setState(() {
        _selectedMediaPath = picker.path;
        _selectedMediaIsVideo = true;
        _pickedImageBytes = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLanguageService.instance.t('failed_pick_video')}: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _createPost() async {
    final text = _newPostController.text.trim();
    if (text.isEmpty && _selectedMediaPath == null) return;
    setState(() => _isUploading = true);
    try {
      String? mediaUrl;
      if (_selectedMediaPath != null) {
        if (kIsWeb && _pickedImageBytes != null) {
          mediaUrl = await uploadFileFromBytes(
            _pickedImageBytes!,
            'post_${DateTime.now().millisecondsSinceEpoch}.$_pickedImageExt',
          );
        } else if (_selectedMediaPath != null && _selectedMediaPath != 'picked') {
          mediaUrl = await uploadFile(_selectedMediaPath!);
        }
      }
      final email = widget.currentUser.email ?? '';
      if (email.isEmpty) {
        if (mounted) setState(() => _isUploading = false);
        return;
      }
      await createPost(
        userId: email,
        content: text.isEmpty ? (_selectedMediaIsVideo ? 'Video' : 'Photo') : text,
        mediaUrl: mediaUrl ?? '',
        type: _selectedMediaIsVideo ? 'video' : (_selectedMediaPath != null ? 'image' : 'text'),
      );
      if (mounted) {
        setState(() {
          _isUploading = false;
          _clearPostInput();
        });
        await _loadPosts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLanguageService.instance.t('post_created')), behavior: SnackBarBehavior.floating),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLanguageService.instance.t('failed_to_post')}: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }


  List<_FeedPost> get _filteredPosts {
    // Base list: optionally filter by search.
    List<_FeedPost> base;
    if (_searchQuery.trim().isEmpty) {
      base = _posts;
    } else {
      final q = _searchQuery.toLowerCase();
      base = _posts.where((p) => p.userName.toLowerCase().contains(q)).toList();
    }
    // When Videos pill is active, show only video posts in feed.
    if (_effectiveFeedPillIndex == 1) {
      base = base.where((p) => p.type == 'video').toList();
    }
    return base;
  }

  Future<void> _refreshFeed() async {
    await Future.wait([_loadPosts(), _loadStories()]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final isWide = MediaQuery.sizeOf(context).width >= 768;

    final postCount = _filteredPosts.length;
    final feedColumn = Stack(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, isDark),
            Expanded(
              child: _effectiveFeedPillIndex == 2
                  ? _buildProfileTab(context, isDark)
                  : RefreshIndicator(
                      onRefresh: _refreshFeed,
                      color: BondhuTokens.primary,
                      child: _postsLoading && _posts.isEmpty
                          ? ListView(
                              padding: EdgeInsets.only(
                                bottom: BondhuTokens.mainContentPaddingBottomMobile + 80,
                              ),
                              children: [
                                if (_effectiveFeedPillIndex == 0) ...[
                                  _buildStoriesRow(context, isDark),
                                  _buildCreatePostCard(context, isDark),
                                  const SizedBox(height: 80),
                                ],
                                Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 32,
                                        height: 32,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(BondhuTokens.primary),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Loading feed…',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 14,
                                          color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              cacheExtent: kIsWeb ? 400 : 350,
                              addRepaintBoundaries: true,
                              padding: EdgeInsets.only(
                                bottom: BondhuTokens.mainContentPaddingBottomMobile + 80,
                              ),
                              itemCount: _effectiveFeedPillIndex == 0
                                  ? (postCount == 0 ? 3 : 3 + postCount)
                                  : postCount,
                              itemBuilder: (context, index) {
                                if (_effectiveFeedPillIndex == 0) {
                                  if (index == 0) {
                                    return RepaintBoundary(child: FadeSlideIn(child: _buildStoriesRow(context, isDark)));
                                  }
                                  if (index == 1) {
                                    return RepaintBoundary(child: FadeSlideIn(delay: AppAnimations.fast, child: _buildCreatePostCard(context, isDark)));
                                  }
                                  if (index == 2) {
                                    if (postCount == 0) {
                                      return RepaintBoundary(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 48),
                                          child: Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.article_outlined, size: 48, color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight),
                                                const SizedBox(height: 16),
                                                Text(
                                                  'No posts yet',
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Share your first post above',
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 14,
                                                    color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox(height: 32);
                                  }
                                  final i = index - 3;
                                  final post = _filteredPosts[i];
                                  final isLast = i == postCount - 1;
                                  return RepaintBoundary(
                                    key: ValueKey(post.id),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        FadeSlideIn(
                                          delay: Duration(milliseconds: 60 + i * 50),
                                          offset: const Offset(0, 20),
                                          duration: AppAnimations.medium,
                                          curve: AppAnimations.emphasized,
                                          child: _buildPostItem(
                                            context,
                                            post,
                                            isDark,
                                            isLast: isLast,
                                            isFullWidth: true,
                                          ),
                                        ),
                                        if (!isLast) const SizedBox(height: 12),
                                      ],
                                    ),
                                  );
                                } else {
                                  // Videos pill: video-only feed, full-width posts, no stories/create-post.
                                  if (postCount == 0) {
                                    return RepaintBoundary(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 48),
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.play_circle_outline_rounded, size: 48, color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight),
                                              const SizedBox(height: 16),
                                              Text(
                                                'No videos yet',
                                                style: GoogleFonts.plusJakartaSans(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  final post = _filteredPosts[index];
                                  final isLast = index == postCount - 1;
                                  return RepaintBoundary(
                                    key: ValueKey(post.id),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        FadeSlideIn(
                                          delay: Duration(milliseconds: 60 + index * 50),
                                          offset: const Offset(0, 20),
                                          duration: AppAnimations.medium,
                                          curve: AppAnimations.emphasized,
                                          child: _buildPostItem(
                                            context,
                                            post,
                                            isDark,
                                            isLast: isLast,
                                            isFullWidth: true,
                                          ),
                                        ),
                                        if (!isLast) const SizedBox(height: 12),
                                      ],
                                    ),
                                  );
                                }
                              },
                            ),
                    ),
            ),
          ],
        ),
        if (widget.feedPillIndex == null) _buildFeedBottomNav(context, isDark, isWide),
      ],
    );

    return Scaffold(
      backgroundColor: isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
      body: SafeArea(
        child: Row(
          children: [
            if (isWide)
              SizedBox(width: BondhuTokens.feedColumnWidthDesktop, child: feedColumn)
            else
              Expanded(child: feedColumn),
            if (isWide)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
                    border: Border(
                      left: BorderSide(
                        color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight,
                      ),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'FEED',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: BondhuTokens.feedRightPanelTextSize,
                        fontWeight: FontWeight.w900,
                        color: isDark ? BondhuTokens.borderDark : BondhuTokens.borderLight,
                        height: 1,
                        letterSpacing: -2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    final padH = BondhuTokens.feedHeaderPaddingH;
    final padV = BondhuTokens.feedHeaderPaddingV;
    final buttonSize = _floatingButtonSize;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: padV),
          SizedBox(height: BondhuTokens.feedSearchMarginTop),
          Row(
            children: [
              _buildFloatingSearchButton(isDark),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppAnimations.fast,
                  switchInCurve: AppAnimations.easeOut,
                  switchOutCurve: AppAnimations.easeOut,
                  child: _showSearchBar
                      ? TextField(
                          key: const ValueKey('feed_search_input'),
                          onChanged: (v) => setState(() => _searchQuery = v),
                          style: TextStyle(
                            fontSize: BondhuTokens.fontSize14,
                            color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                          ),
                          decoration: InputDecoration(
                            hintText: AppLanguageService.instance.t('search_users'),
                            hintStyle: TextStyle(
                              color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                              fontSize: BondhuTokens.fontSize14,
                            ),
                            filled: true,
                            fillColor: isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.inputBgLight,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        )
                      : SizedBox(
                          key: const ValueKey('feed_search_spacer'),
                          height: buttonSize,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              _buildFloatingNotificationButton(isDark),
            ],
          ),
        ],
      ),
    );
  }

  static const double _floatingButtonSize = 36.0;

  Widget _buildFloatingSearchButton(bool isDark) {
    final size = _floatingButtonSize;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _showSearchBar = !_showSearchBar),
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _showSearchBar
                ? BondhuTokens.primary
                : (isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight),
            borderRadius: BorderRadius.circular(size / 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.search_rounded,
            size: 20,
            color: _showSearchBar
                ? Colors.black
                : (isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingNotificationButton(bool isDark) {
    const size = _floatingButtonSize;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onOpenNotifications ?? () {},
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight,
            borderRadius: BorderRadius.circular(size / 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.notifications_outlined,
            size: 20,
            color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
          ),
        ),
      ),
    );
  }

  /// BackdropFilter can cause ANR on mobile; use only on web.
  Widget _wrapBlurIfWeb({required ImageFilter filter, required Widget child}) {
    if (kIsWeb) {
      return BackdropFilter(filter: filter, child: child);
    }
    return child;
  }

  Widget _buildStoriesRow(BuildContext context, bool isDark) {
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    const padL = 20.0;
    final padR = isWide ? 48.0 : 20.0;
    return Padding(
      padding: EdgeInsets.only(left: padL, right: padR, top: 12, bottom: 4),
      child: Column(
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
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAddStory(context, isDark),
                  if (_storiesLoading) ...[
                    const SizedBox(width: 10),
                    SizedBox(
                      width: BondhuTokens.feedStoryBoxWidth,
                      height: BondhuTokens.feedStoryBoxHeight,
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  ] else ...[
                    ...List.generate(_stories.length, (i) {
                      final story = _stories[i];
                      return Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 10 : 0, right: 10),
                        child: _buildStoryBox(context, story, i, isDark),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Add Story: minimal rounded card, subtle border and fill.
  Widget _buildAddStory(BuildContext context, bool isDark) {
    final w = BondhuTokens.feedStoryBoxWidth;
    final h = BondhuTokens.feedStoryBoxHeight;
    final r = BondhuTokens.feedStoryBoxRadius;
    return SizedBox(
      width: w,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _pickAndUploadStory,
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
    );
  }

  /// Dedicated rounded box for each story: story image fills the box, avatar in a circle, name at bottom.
  Widget _buildStoryBox(BuildContext context, StoryItem story, int index, bool isDark) {
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
        onTap: () {
          HapticFeedback.lightImpact();
          _openStory(index);
        },
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
                // Story image (or gradient placeholder)
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
                    error: _storyBoxPlaceholder(isDark),
                  )
                else
                  _storyBoxPlaceholder(isDark),
                // Bottom gradient for name readability
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
                // User name at bottom
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
                // Avatar circle (top-left inside box)
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
                          child: const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                        ),
                        error: Icon(Icons.person_rounded, size: avatarSize * 0.5, color: BondhuTokens.textMutedDark),
                      ),
                    ),
                  ),
                ),
                // Simple insights badge for your own story (views / likes)
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

  Widget _storyBoxPlaceholder(bool isDark) {
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
        child: Icon(Icons.image_outlined, size: 24, color: isDark ? BondhuTokens.textMutedDark : const Color(0xFF94A3B8)),
      ),
    );
  }

  Widget _buildCreatePostCardFill(
    BuildContext context,
    bool isDark, {
    required double padding,
    required double gap,
    required double avatarSize,
    required bool canPost,
    bool paddingOnly = false,
  }) {
    final column = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: _isOwner ? () => _showEditProfileSheet(context, isDark) : null,
                    child: Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE5E7EB).withValues(alpha: 0.8),
                          width: 1,
                        ),
                        image: _userAvatarUrl != null && _userAvatarUrl!.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(_userAvatarUrl!, scale: 1.0),
                                fit: BoxFit.cover,
                              )
                            : null,
                        color: _userAvatarUrl == null || _userAvatarUrl!.isEmpty
                            ? (isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.borderLight)
                            : null,
                      ),
                      child: _userAvatarUrl == null || _userAvatarUrl!.isEmpty
                          ? Icon(Icons.person, color: BondhuTokens.textMutedDark, size: avatarSize * 0.5)
                          : null,
                    ),
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: BondhuTokens.feedCreatePostStatusDotSize,
                      height: BondhuTokens.feedCreatePostStatusDotSize,
                      decoration: BoxDecoration(
                        color: BondhuTokens.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? BondhuTokens.surfaceDarkCard : BondhuTokens.surfaceLight,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(width: gap),
              Expanded(
                child: AnimatedContainer(
                  duration: BondhuTokens.motionFast,
                  curve: BondhuTokens.motionEase,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                    ),
                  ),
                  child: TextField(
                    controller: _newPostController,
                    onChanged: (_) => setState(() {}),
                    maxLines: null,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: AppLanguageService.instance.t('whats_on_mind'),
                      hintStyle: TextStyle(
                        color: isDark ? const Color(0xFF71717A) : const Color(0xFF9CA3AF),
                        fontSize: 14,
                      ),
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      isDense: true,
                    ),
                    style: TextStyle(
                      color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_selectedMediaPath != null) ...[
            const SizedBox(height: 8),
            Stack(
              alignment: Alignment.topRight,
              children: [
                Container(
                  height: 176,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE5E7EB).withValues(alpha: 0.6),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _selectedMediaIsVideo
                      ? const Center(child: Icon(Icons.videocam, size: 48, color: Colors.grey))
                      : Image.network(_selectedMediaPath!, fit: BoxFit.cover, errorBuilder: (_, error, stackTrace) => const Icon(Icons.image)),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _selectedMediaPath = null),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: padding * 0.5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _createPostActionButton(context, isDark, Icons.image_outlined, true, _pickImageForPost),
                  const SizedBox(width: 2),
                  _createPostActionButton(context, isDark, Icons.videocam_outlined, false, _pickVideoForPost),
                ],
              ),
              Material(
                color: BondhuTokens.primary,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: (_isUploading || !canPost) ? null : _createPost,
                  borderRadius: BorderRadius.circular(999),
                  child: Opacity(
                    opacity: (_isUploading || !canPost) ? 0.4 : 1,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),   // px-3.5 py-1.5
                      child: Text(
                        _isUploading ? 'Posting...' : 'Post',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
    );
    if (paddingOnly) {
      return Padding(
        padding: EdgeInsets.all(padding),
        child: column,
      );
    }
    return Container(
      color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.8),
      padding: EdgeInsets.all(padding),
      child: column,
    );
  }

  Widget _buildCreatePostCard(BuildContext context, bool isDark) {
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    final marginH = BondhuTokens.feedCreatePostMarginH;
    final marginTop = BondhuTokens.feedCreatePostMarginTop;
    final marginBottom = BondhuTokens.feedCreatePostMarginBottom;
    final padding = isWide ? BondhuTokens.feedCreatePostPaddingDesktop : BondhuTokens.feedCreatePostPadding;
    final gap = isWide ? 12.0 : 10.0;
    final avatarSize = BondhuTokens.feedCreatePostAvatarSize;
    final canPost = _newPostController.text.trim().isNotEmpty || _selectedMediaPath != null;
    if (kIsWeb) {
      return Container(
        margin: EdgeInsets.fromLTRB(marginH, marginTop, marginH, marginBottom),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(BondhuTokens.radiusXl),
          color: isDark ? BondhuTokens.surfaceDark : Colors.white.withValues(alpha: 0.92),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE8EDF2),
          ),
          boxShadow: isDark ? BondhuTokens.cardShadowDark : BondhuTokens.cardShadowLight,
        ),
        child: RepaintBoundary(
          child: _buildCreatePostCardFill(
            context,
            isDark,
            padding: padding,
            gap: gap,
            avatarSize: avatarSize,
            canPost: canPost,
            paddingOnly: true,
          ),
        ),
      );
    }
    return Container(
      margin: EdgeInsets.fromLTRB(marginH, marginTop, marginH, marginBottom),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(BondhuTokens.radiusXl),
          child: _wrapBlurIfWeb(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE8EDF2),
                ),
                boxShadow: isDark ? BondhuTokens.cardShadowDark : BondhuTokens.cardShadowLight,
              ),
              child: _buildCreatePostCardFill(
                context,
                isDark,
                padding: padding,
                gap: gap,
                avatarSize: avatarSize,
                canPost: canPost,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _createPostActionButton(BuildContext context, bool isDark, IconData icon, bool isPhoto, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(icon, size: isPhoto ? 20 : 18, color: isDark ? const Color(0xFF71717A) : const Color(0xFF9CA3AF)),
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

  /// Floating bottom nav pill: Home / Videos / Profile (website: absolute bottom-2 md:bottom-6, rounded-full, gap-8).
  Widget _buildFeedBottomNav(BuildContext context, bool isDark, bool isWide) {
    const activeColor = Color(0xFF00C896);
    final inactiveColor = isDark ? const Color(0xFF71717A) : const Color(0xFF6B7280);
    final bottom = isWide ? 24.0 : 8.0;
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: Center(
        child: RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: _wrapBlurIfWeb(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? BondhuTokens.surfaceDark.withValues(alpha: 0.95) : BondhuTokens.surfaceLight.withValues(alpha: 0.98),
                border: Border.all(
                  color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE5E7EB),
                ),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _feedPillButton(Icons.home_rounded, 0, activeColor, inactiveColor),
                  const SizedBox(width: 32),
                  _feedPillButton(Icons.play_circle_outline_rounded, 1, activeColor, inactiveColor),
                  const SizedBox(width: 32),
                  _feedPillButton(Icons.person_outline_rounded, 2, activeColor, inactiveColor),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _feedPillButton(IconData icon, int index, Color activeColor, Color inactiveColor) {
    final isActive = _effectiveFeedPillIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _setFeedPillIndex(index),
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 24,
            color: isActive ? activeColor : inactiveColor,
          ),
        ),
      ),
    );
  }

  /// Profile tab: same design and actions as website (viewing profile, back, Edit / Follow+Message, followers modal).
  Widget _buildProfileTab(BuildContext context, bool isDark) {
    final padH = BondhuTokens.feedProfilePaddingH;
    final avatarSize = BondhuTokens.feedProfileAvatarSize;
    final statsGap = BondhuTokens.feedProfileStatsGap;
    final borderColor = isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight;
    final labelColor = isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight;
    final primaryColor = BondhuTokens.primary;
    final myEmail = widget.currentUser.email ?? '';

    final profilePosts = _profileViewTab == 1
        ? _filteredPosts.where((p) => p.userId == _activeProfileUserId && p.type == 'video').toList()
        : _profileViewTab == 2
            ? _filteredPosts.where((p) => p.savedBy.contains(myEmail)).toList() // saved only for current user
            : _filteredPosts.where((p) => p.userId == _activeProfileUserId).toList();

    return FadeSlideIn(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: padH,
          right: padH,
          top: BondhuTokens.feedProfilePaddingTop,
          bottom: BondhuTokens.mainContentPaddingBottomMobile + 80,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_viewingProfile != null) ...[
              GestureDetector(
                onTap: () {
                  setState(() => _viewingProfile = null);
                  _setFeedPillIndex(0);
                },
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_back_ios_new, size: 18, color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight),
                      const SizedBox(width: 8),
                      Text(
                        'Back',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _isOwner ? () => _showEditProfileSheet(context, isDark) : null,
                  child: Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: primaryColor, width: BondhuTokens.feedProfileAvatarBorder),
                      boxShadow: BondhuTokens.logoGlow,
                    ),
                    child: ClipOval(
                      child: _activeProfileAvatar != null && _activeProfileAvatar!.isNotEmpty
                          ? _premiumNetworkImage(
                              _activeProfileAvatar!,
                              fit: BoxFit.cover,
                              error: Icon(Icons.person, size: avatarSize * 0.5, color: labelColor),
                            )
                          : Icon(Icons.person, size: avatarSize * 0.5, color: labelColor),
                    ),
                  ),
                ),
                SizedBox(width: statsGap),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _profileStat(isDark, _profilePostsCount, 'POSTS'),
                        GestureDetector(
                          onTap: () => _showFollowersFollowingSheet(context, isDark, true),
                          child: _profileStat(isDark, _profileFollowersCount, 'FOLLOWERS'),
                        ),
                        GestureDetector(
                          onTap: () => _showFollowersFollowingSheet(context, isDark, false),
                          child: _profileStat(isDark, _profileFollowingCount, 'FOLLOWING'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _activeProfileName,
              style: GoogleFonts.plusJakartaSans(
                fontSize: BondhuTokens.feedProfileNameSize,
                fontWeight: FontWeight.w700,
                color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                height: 1.2,
              ),
            ),
            SizedBox(height: BondhuTokens.feedProfileBioMarginTop),
            Text(
              _activeProfileBio,
              style: GoogleFonts.plusJakartaSans(
                fontSize: BondhuTokens.fontSize14,
                color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF4B5563),
                height: 1.4,
              ),
            ),
            if (_activeProfileLocation != null && _activeProfileLocation!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 14, color: labelColor),
                  const SizedBox(width: 6),
                  Text(
                    _activeProfileLocation!,
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: labelColor),
                  ),
                ],
              ),
            ],
            SizedBox(height: BondhuTokens.feedProfileButtonsMarginBottom),
            // Buttons: Edit Profile (owner) or Follow + Message (other user) — website same
            if (_isOwner)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _showEditProfileSheet(context, isDark),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF1F5F9),
                    foregroundColor: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                    side: BorderSide(color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(AppLanguageService.instance.t('edit_profile'), style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Material(
                      color: _isFollowingActiveProfile
                          ? (isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFE5E7EB))
                          : BondhuTokens.primary,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: _toggleFollow,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Center(
                            child: Text(
                              _isFollowingActiveProfile ? AppLanguageService.instance.t('following') : AppLanguageService.instance.t('follow'),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _isFollowingActiveProfile
                                    ? (isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight)
                                    : Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: BondhuTokens.feedProfileButtonsGap),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => widget.onNavigateToChat?.call(_activeProfileUserId),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFE5E7EB),
                        foregroundColor: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                        side: BorderSide(color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(AppLanguageService.instance.t('message'), style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            SizedBox(height: BondhuTokens.feedProfileTabBorderTop),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  _profileTabButton(isDark, 0, Icons.grid_on_rounded),
                  _profileTabButton(isDark, 1, Icons.play_circle_outline_rounded),
                  _profileTabButton(isDark, 2, Icons.bookmark_outline_rounded),
                ],
              ),
            ),
            // Grid: 3 columns, aspect-square, gap-0.5 (website)
            if (profilePosts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: BondhuTokens.feedProfileEmptyPaddingVertical),
                child: Center(
                  child: Text(
                    'No posts yet.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: labelColor,
                    ),
                  ),
                ),
              )
            else
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: BondhuTokens.feedProfileGridGap,
                crossAxisSpacing: BondhuTokens.feedProfileGridGap,
                childAspectRatio: 1,
                children: profilePosts.map((post) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showPostDetail(context, post, isDark),
                    onLongPress: () => _showPostMoreSheet(context, post, isDark),
                    child: Container(
                      color: isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.borderLight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (post.mediaUrl.isNotEmpty)
                            _premiumNetworkImage(
                              post.mediaUrl,
                              fit: BoxFit.cover,
                              cacheWidth: 300, // Optimize grid images
                              cacheHeight: 300,
                              error: Icon(Icons.image_not_supported, color: labelColor),
                            )
                          else
                            Icon(Icons.text_fields, color: labelColor),
                          if (post.type == 'video')
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            SizedBox(height: BondhuTokens.feedProfileGridPaddingBottom),
          ],
        ),
      ),
    );
  }

  Widget _profileStat(bool isDark, int value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: GoogleFonts.plusJakartaSans(
            fontSize: BondhuTokens.feedProfileNameSize,
            fontWeight: FontWeight.w700,
            color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: BondhuTokens.fontSize10,
            color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _profileTabButton(bool isDark, int index, IconData icon) {
    final isActive = _profileViewTab == index;
    final activeColor = isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.primary;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _profileViewTab = index),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isActive ? (isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.primary) : Colors.transparent,
                  width: 2,
                ),
              ),
              color: isActive
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : BondhuTokens.primary.withValues(alpha: 0.08))
                  : Colors.transparent,
            ),
            child: Icon(icon, size: 20, color: isActive ? activeColor : (isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight)),
          ),
        ),
      ),
    );
  }

  Widget _buildPostItem(BuildContext context, _FeedPost post, bool isDark, {bool isLast = false, bool isFullWidth = false}) {
    final myEmail = widget.currentUser.email ?? '';
    final isLiked = post.likesList.contains(myEmail);
    final likeCount = post.likesCount;
    final expanded = _expandedComments[post.id] ?? false;
    final padH = BondhuTokens.feedPostItemPaddingH;
    final avatarR = BondhuTokens.feedPostAvatarSize / 2;
    final fontSize = BondhuTokens.fontSize14;
    const iconSize = 20.0;
    final horizontal = isFullWidth ? 0.0 : padH;
    return Container(
      padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, BondhuTokens.feedPostItemPaddingBottom),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(
                  color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight,
                ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: BondhuTokens.feedPostItemMarginBottom),
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _navigateToProfile(post.userId),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: avatarR,
                      backgroundColor: isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.borderLight,
                      backgroundImage: post.avatar.isNotEmpty
                          ? NetworkImage(post.avatar, scale: 1.0)
                          : null,
                    ),
                    SizedBox(width: BondhuTokens.feedPostAvatarGap),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          post.userName,
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            fontSize: fontSize,
                            color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                          ),
                        ),
                        Text(
                          '${post.timeAgo} ago',
                          style: TextStyle(
                            fontSize: BondhuTokens.responsive3(context, 9.0, 10.0, 10.0),
                            color: BondhuTokens.textMutedDark,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _showPostMoreSheet(context, post, isDark),
                icon: Icon(Icons.more_horiz, color: BondhuTokens.textMutedDark, size: iconSize),
                style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(36, 36)),
              ),
            ],
          ),
          SizedBox(height: padH * 0.75),
          Text(
            post.content,
            style: TextStyle(
              fontSize: fontSize,
              color: isDark ? const Color(0xFFE4E4E7) : const Color(0xFF374151),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          if (post.mediaUrl.isNotEmpty)
            GestureDetector(
              onTap: () => _showPostDetail(context, post, isDark),
              onDoubleTap: () => _toggleLike(post),
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  // In video tab we want a taller, more immersive frame.
                  maxHeight: _effectiveFeedPillIndex == 1
                      ? 420
                      : BondhuTokens.feedPostMediaMaxHeight,
                ),
                color: isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
                child: _premiumNetworkImage(
                  post.mediaUrl,
                  fit: _effectiveFeedPillIndex == 1 ? BoxFit.cover : BoxFit.contain,
                  loading: Container(
                    height: 200,
                    color: isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.bgLight,
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: Container(
                    height: 200,
                    color: isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.bgLight,
                    child: Icon(Icons.image_not_supported, color: BondhuTokens.textMutedDark),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          // Action bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  ScaleTap(
                    onTap: () => _toggleLike(post),
                    child: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      size: iconSize,
                      color: isLiked ? Colors.red : (isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight),
                    ),
                  ),
                  SizedBox(width: padH * 0.5),
                  ScaleTap(
                    onTap: () => setState(() => _expandedComments[post.id] = !expanded),
                    child: Icon(
                      Icons.chat_bubble_outline,
                      size: iconSize,
                      color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                    ),
                  ),
                  SizedBox(width: padH * 0.5),
                  ScaleTap(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(AppLanguageService.instance.t('share')), behavior: SnackBarBehavior.floating),
                      );
                    },
                    child: Icon(
                      Icons.send_outlined,
                      size: iconSize,
                      color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                    ),
                  ),
                ],
              ),
              ScaleTap(
                onTap: () => _toggleSave(post),
                child: Icon(
                  post.savedBy.contains(myEmail) ? Icons.bookmark : Icons.bookmark_border,
                  size: iconSize,
                  color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                ),
              ),
            ],
          ),
          Text(
            '$likeCount likes • ${_allCommentsFor(post).length} comments',
            style: GoogleFonts.plusJakartaSans(
              fontSize: BondhuTokens.responsive3(context, 11.0, 12.0, 12.0),
              fontWeight: FontWeight.w600,
              color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
            ),
          ),
          // Inline comments
          if (expanded) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight,
                  ),
                ),
              ),
              child: Column(
                children: [
                  if (_allCommentsFor(post).isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No comments yet.',
                        style: TextStyle(
                          fontSize: BondhuTokens.fontSize12,
                          color: BondhuTokens.textMutedDark,
                        ),
                      ),
                    )
                  else
                    ..._allCommentsFor(post).map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.borderLight,
                              backgroundImage: c.avatar.isNotEmpty
                                  ? NetworkImage(c.avatar, scale: 1.0)
                                  : null,
                              child: c.avatar.isEmpty ? Icon(Icons.person, size: 14, color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight) : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${c.name} ',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: BondhuTokens.fontSize12,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                                    ),
                                  ),
                                  Text(
                                    c.text,
                                    style: TextStyle(
                                      fontSize: BondhuTokens.fontSize12,
                                      color: isDark ? const Color(0xFFD4D4D8) : const Color(0xFF52525B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.borderLight,
                        backgroundImage: _userAvatarUrl != null && _userAvatarUrl!.isNotEmpty
                            ? NetworkImage(_userAvatarUrl!, scale: 1.0)
                            : null,
                        child: _userAvatarUrl == null || _userAvatarUrl!.isEmpty
                            ? Icon(Icons.person, size: 14, color: BondhuTokens.textMutedDark)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _commentInputs[post.id] = v),
                          decoration: InputDecoration(
                            hintText: AppLanguageService.instance.t('add_comment'),
                            hintStyle: TextStyle(
                              color: BondhuTokens.textMutedDark,
                              fontSize: BondhuTokens.fontSize12,
                            ),
                            filled: true,
                            fillColor: isDark ? BondhuTokens.inputBgDark : BondhuTokens.inputBgLight,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(
                                color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            isDense: true,
                          ),
                          style: TextStyle(
                            fontSize: BondhuTokens.fontSize12,
                            color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => _submitComment(post),
                        child: Text(
                          'Post',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: BondhuTokens.fontSize12,
                            fontWeight: FontWeight.w700,
                            color: BondhuTokens.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedPost {
  final String id;
  final String userName;
  final String userId;
  final String avatar;
  final String timeAgo;
  final String content;
  final String mediaUrl;
  final String type;
  final List<String> likesList;
  final List<String> savedBy;
  final List<_FeedComment> comments;

  _FeedPost({
    required this.id,
    required this.userName,
    required this.userId,
    required this.avatar,
    required this.timeAgo,
    required this.content,
    required this.mediaUrl,
    required this.type,
    required this.likesList,
    required this.savedBy,
    required this.comments,
  });

  int get likesCount => likesList.length;
  int get commentsCount => comments.length;

  _FeedPost copyWith({
    String? content,
    List<String>? likesList,
    List<String>? savedBy,
    List<_FeedComment>? comments,
  }) =>
      _FeedPost(
        id: id,
        userName: userName,
        userId: userId,
        avatar: avatar,
        timeAgo: timeAgo,
        content: content ?? this.content,
        mediaUrl: mediaUrl,
        type: type,
        likesList: likesList ?? this.likesList,
        savedBy: savedBy ?? this.savedBy,
        comments: comments ?? this.comments,
      );
}

class _FeedVideoPlayer extends StatefulWidget {
  const _FeedVideoPlayer({required this.url});

  final String url;

  @override
  State<_FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<_FeedVideoPlayer> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (_) {
      if (mounted) setState(() => _controller = null);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
    }
    return Center(
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9,
        child: VideoPlayer(c),
      ),
    );
  }
}

class _FeedComment {
  final String id;
  final String name;
  final String avatar;
  final String text;

  _FeedComment({
    required this.id,
    required this.name,
    required this.avatar,
    required this.text,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'avatar': avatar,
        'text': text,
        'timestamp': DateTime.now().toIso8601String(),
      };
}

/// Subtle pulse animation for the "add story" circle.
class _StoryPulse extends StatefulWidget {
  const _StoryPulse({required this.child});

  final Widget child;

  @override
  State<_StoryPulse> createState() => _StoryPulseState();
}

class _StoryPulseState extends State<_StoryPulse> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1, end: 1.04).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
      child: widget.child,
    );
  }
}

/// Double-tap overlay that shows a heart burst animation.
class _DoubleTapHeart extends StatefulWidget {
  const _DoubleTapHeart({
    required this.onDoubleTap,
    required this.child,
  });

  final VoidCallback onDoubleTap;
  final Widget child;

  @override
  State<_DoubleTapHeart> createState() => _DoubleTapHeartState();
}

class _DoubleTapHeartState extends State<_DoubleTapHeart> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scale = Tween<double>(begin: 0.3, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.5, curve: ClampedCurve(Curves.elasticOut))),
    );
    _opacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.3, 1, curve: Curves.easeOut)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    widget.onDoubleTap();
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: _onDoubleTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              if (_controller.status != AnimationStatus.forward && _controller.value == 0) {
                return const SizedBox.shrink();
              }
              return IgnorePointer(
                child: Opacity(
                  opacity: _opacity.value.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: _scale.value,
                    child: Icon(
                      Icons.favorite_rounded,
                      size: 88,
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Like button with fill and scale animation.
class _AnimatedLikeButton extends StatefulWidget {
  const _AnimatedLikeButton({
    required this.isLiked,
    required this.size,
    required this.onTap,
  });

  final bool isLiked;
  final double size;
  final VoidCallback onTap;

  @override
  State<_AnimatedLikeButton> createState() => _AnimatedLikeButtonState();
}

class _AnimatedLikeButtonState extends State<_AnimatedLikeButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scale = Tween<double>(begin: 1, end: 1.35).animate(
      CurvedAnimation(parent: _controller, curve: const ClampedCurve(Curves.easeOutBack)),
    );
  }

  @override
  void didUpdateWidget(_AnimatedLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLiked && !oldWidget.isLiked) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: widget.onTap,
      scale: 0.88,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(
          scale: _scale.value,
          child: child,
        ),
        child: AnimatedSwitcher(
          duration: AppAnimations.fast,
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: Icon(
            widget.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: ValueKey(widget.isLiked),
            size: widget.size,
            color: widget.isLiked ? Colors.red : (BondhuTokens.textMutedDark),
          ),
        ),
      ),
    );
  }
}

/// Hides scrollbar for horizontal stories row (website: no-scrollbar).
class _NoScrollbarScrollBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

