import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design_tokens.dart';
import '../services/supabase_service.dart';

/// Full-screen story viewer: progress, image, prev/next, delete (owner), like, comment, activity.
class StoryOverlay extends StatefulWidget {
  const StoryOverlay({
    super.key,
    required this.stories,
    required this.initialIndex,
    required this.currentUserEmail,
    required this.currentUserName,
    required this.currentUserAvatar,
    required this.isDark,
    required this.onClose,
    required this.onStoriesUpdated,
  });

  final List<StoryItem> stories;
  final int initialIndex;
  final String? currentUserEmail;
  final String? currentUserName;
  final String? currentUserAvatar;
  final bool isDark;
  final VoidCallback onClose;
  final VoidCallback onStoriesUpdated;

  @override
  State<StoryOverlay> createState() => _StoryOverlayState();
}

class _StoryOverlayState extends State<StoryOverlay> {
  late List<StoryItem> _stories;
  late int _currentIndex;
  Timer? _progressTimer;
  double _progress = 0;
  static const _durationSec = 10;
  bool _paused = false;
  bool _showActivity = false;
  final TextEditingController _commentController = TextEditingController();

  StoryItem get _currentStory =>
      _stories[_currentIndex.clamp(0, _stories.length - 1)];

  bool get _isOwner =>
      widget.currentUserEmail != null &&
      _currentStory.userId.toLowerCase() == widget.currentUserEmail!.toLowerCase();

  bool get _hasLiked =>
      widget.currentUserEmail != null &&
      _currentStory.likes.contains(widget.currentUserEmail!.toLowerCase());

  @override
  void initState() {
    super.initState();
    _stories = List<StoryItem>.from(widget.stories);
    _currentIndex = widget.initialIndex.clamp(0, _stories.length - 1);
    _progress = 0;
    _startProgress();
    _maybeAddView();
  }

  void _maybeAddView() {
    if (_isOwner) return;
    final email = widget.currentUserEmail?.trim().toLowerCase();
    if (email == null || email.isEmpty) return;
    final views = List<Map<String, dynamic>>.from(_currentStory.views);
    if (views.any((v) => (v['email'] as String? ?? '').toLowerCase() == email)) return;
    views.add({
      'email': widget.currentUserEmail,
      'name': widget.currentUserName ?? email.split('@').first,
      'avatar': widget.currentUserAvatar ?? defaultAvatar(email),
      'time': DateTime.now().toIso8601String(),
    });
    final updated = _currentStory.copyWith(views: views);
    _stories[_currentIndex] = updated;
    updateStory(_currentStory.id, {'views': views}).then((_) {
      widget.onStoriesUpdated();
      if (mounted) setState(() {});
    });
  }

  void _startProgress() {
    _progressTimer?.cancel();
    if (_paused) return;
    const step = 0.01; // 100ms * 10% = 1s -> 10s total
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _paused) return;
      setState(() {
        _progress += step / _durationSec;
        if (_progress >= 1) {
          _progress = 1;
          _progressTimer?.cancel();
          _next();
        }
      });
    });
  }

  void _pause() {
    if (!_paused) {
      _paused = true;
      _progressTimer?.cancel();
      if (mounted) setState(() {});
    }
  }

  void _resume() {
    if (_paused) {
      _paused = false;
      if (mounted) setState(() {});
      _startProgress();
    }
  }

  void _next() {
    if (_currentIndex < _stories.length - 1) {
      setState(() {
        _currentIndex++;
        _progress = 0;
        _showActivity = false;
        _commentController.clear();
      });
      _startProgress();
      _maybeAddView();
    } else {
      widget.onClose();
    }
  }

  void _prev() {
    _progressTimer?.cancel();
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _progress = 0;
        _showActivity = false;
        _commentController.clear();
      });
      _startProgress();
      _maybeAddView();
    } else {
      _progress = 0;
      _startProgress();
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _deleteStory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF1A1A1A) : Colors.white,
        title: const Text('Delete story?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await deleteStory(_currentStory.id);
      widget.onStoriesUpdated();
      widget.onClose();
    }
  }

  Future<void> _toggleLike() async {
    final email = widget.currentUserEmail?.trim().toLowerCase();
    if (email == null || email.isEmpty) return;
    final likes = List<String>.from(_currentStory.likes);
    if (likes.contains(email)) {
      likes.remove(email);
    } else {
      likes.add(email);
    }
    _stories[_currentIndex] = _currentStory.copyWith(likes: likes);
    if (mounted) setState(() {});
    await updateStory(_currentStory.id, {'likes': likes});
    widget.onStoriesUpdated();
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    final commentObj = {
      'userName': widget.currentUserName ?? widget.currentUserEmail?.split('@').first ?? 'You',
      'userAvatar': widget.currentUserAvatar ?? defaultAvatar(widget.currentUserEmail),
      'text': text,
      'time': 'Now',
    };
    final comments = List<String>.from(_currentStory.comments)..add(jsonEncode(commentObj));
    _stories[_currentIndex] = _currentStory.copyWith(comments: comments);
    _commentController.clear();
    if (mounted) setState(() {});
    await updateStory(_currentStory.id, {'comments': comments});
    widget.onStoriesUpdated();
  }

  @override
  Widget build(BuildContext context) {
    final story = _currentStory;
    final isDark = widget.isDark;
    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Progress bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: List.generate(_stories.length, (i) {
                    final fill = i < _currentIndex ? 1.0 : (i == _currentIndex ? _progress : 0.0);
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: fill.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(2),
                              ),
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
          // Image (tap and hold to pause)
          GestureDetector(
            onTapDown: (_) => _pause(),
            onTapUp: (_) => _resume(),
            onTapCancel: _resume,
            child: Center(
              child: Image.network(
                story.mediaUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, e, stackTrace) => const Icon(Icons.broken_image, size: 64, color: Colors.white54),
              ),
            ),
          ),
          // Left tap -> prev
          Positioned(left: 0, top: 0, bottom: 0, width: MediaQuery.sizeOf(context).width * 0.3, child: GestureDetector(onTap: _prev)),
          // Right tap -> next
          Positioned(right: 0, top: 0, bottom: 0, width: MediaQuery.sizeOf(context).width * 0.7, child: GestureDetector(onTap: _next)),
          // Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: NetworkImage(story.avatar),
                      onBackgroundImageError: (_, error) {},
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            story.userName,
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                          Text(
                            story.time,
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    if (_isOwner)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                        onPressed: _deleteStory,
                      ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bottom: like, comment, activity
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _showActivity ? _buildActivityPanel(isDark) : _buildBottomBar(isDark, story),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool isDark, StoryItem story) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              decoration: InputDecoration(
                hintText: 'Reply to story...',
                hintStyle: TextStyle(color: Colors.white70, fontSize: 14),
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              onSubmitted: (_) => _sendComment(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(_hasLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: _hasLiked ? Colors.red : Colors.white, size: 28),
            onPressed: _toggleLike,
          ),
          if (_commentController.text.trim().isNotEmpty)
            IconButton(
              icon: const Icon(Icons.send_rounded, color: BondhuTokens.primary, size: 24),
              onPressed: _sendComment,
            ),
          if (_isOwner)
            TextButton.icon(
              onPressed: () => setState(() => _showActivity = true),
              icon: const Icon(Icons.insights_rounded, color: Colors.white, size: 20),
              label: Text('Activity', style: GoogleFonts.inter(fontSize: 12, color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Widget _buildActivityPanel(bool isDark) {
    final story = _currentStory;
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.5,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : const Color(0xFF1A1A1A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Story insights', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => setState(() => _showActivity = false),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _activityChip(Icons.visibility_rounded, '${story.views.length}', 'Views'),
              const SizedBox(width: 16),
              _activityChip(Icons.favorite_rounded, '${story.likes.length}', 'Likes'),
              const SizedBox(width: 16),
              _activityChip(Icons.comment_rounded, '${story.comments.length}', 'Comments'),
            ],
          ),
          const SizedBox(height: 16),
          Text('Comments', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
          const SizedBox(height: 8),
          Expanded(
            child: story.comments.isEmpty
                ? Center(child: Text('No comments yet', style: GoogleFonts.inter(fontSize: 13, color: Colors.white54)))
                : ListView.builder(
                    itemCount: story.comments.length,
                    itemBuilder: (context, i) {
                      try {
                        final map = jsonDecode(story.comments[i]) as Map<String, dynamic>;
                        final userName = map['userName'] as String? ?? 'User';
                        final text = map['text'] as String? ?? '';
                        return Padding(
                          key: ValueKey('comment_$i'),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundImage: NetworkImage(map['userAvatar'] as String? ?? defaultAvatar(null)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(userName, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                                    Text(text, style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      } catch (_) {
                        return const SizedBox.shrink();
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _activityChip(IconData icon, String count, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 6),
          Text(count, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
        ],
      ),
    );
  }
}

/// Fills a fraction of parent width (for progress bar).
class FractionallySizedBox extends StatelessWidget {
  const FractionallySizedBox({
    super.key,
    required this.widthFactor,
    required this.child,
  });
  final double widthFactor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = (constraints.maxWidth * widthFactor.clamp(0.0, 1.0)).clamp(0.0, double.infinity);
        return SizedBox(width: w, child: child);
      },
    );
  }
}
