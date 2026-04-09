import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/notification_service.dart';

typedef NotificationTapCallback = void Function(AppNotification notification);

/// Dedicated full-screen notifications screen with smart grouping & filters.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.isDark,
    required this.onNotificationTap,
  });

  final bool isDark;
  final NotificationTapCallback onNotificationTap;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _filter = 'all'; // all, messages, social, system, unread

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Scaffold(
      backgroundColor: isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, isDark),
            _buildFilters(isDark),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<AppNotification>>(
                stream: NotificationService.instance.stream,
                initialData: NotificationService.instance.list,
                builder: (context, snapshot) {
                  final list = snapshot.data ?? const <AppNotification>[];
                  final filtered = _applyFilter(list);
                  if (filtered.isEmpty) {
                    if (list.isEmpty) {
                      return _buildEmpty(isDark);
                    }
                    return _buildEmpty(
                      isDark,
                      message: AppLanguageService.instance.t('notifications_empty_filter'),
                    );
                  }
                  final grouped = _groupByDay(filtered);
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: grouped.length,
                    itemBuilder: (context, index) {
                      final entry = grouped[index];
                      final label = entry.key;
                      final items = entry.value;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              label,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                                color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                              ),
                            ),
                          ),
                          ...items.map((n) => _buildNotificationTile(n, isDark)),
                          const SizedBox(height: 4),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    final unread = NotificationService.instance.unreadCount;
    final t = AppLanguageService.instance.t;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF020617), Color(0xFF0F172A)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE0FBEA), Color(0xFFCCFBF1)],
              ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded,
                color: isDark ? Colors.white : const Color(0xFF0F172A)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('notifications'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                unread > 0
                    ? t('notifications_unread_count').replaceFirst('{count}', unread.toString())
                    : t('notifications_all_caught_up'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: isDark
                      ? BondhuTokens.textMutedDark
                      : const Color(0xFF4B5563),
                ),
              ),
            ],
          ),
          const Spacer(),
          if (unread > 0)
            TextButton(
              onPressed: () {
                NotificationService.instance.markAllRead();
                setState(() {});
              },
              child: Text(
                t('notifications_mark_all_read'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF5EEAD4) : BondhuTokens.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilters(bool isDark) {
    final baseStyle = GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500);
    final t = AppLanguageService.instance.t;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _filterChip(t('notifications_filter_all'), 'all', isDark, baseStyle),
          _filterChip(t('notifications_filter_unread'), 'unread', isDark, baseStyle),
          _filterChip(t('notifications_filter_messages'), 'messages', isDark, baseStyle),
          _filterChip(t('notifications_filter_social'), 'social', isDark, baseStyle),
          _filterChip(t('notifications_filter_system'), 'system', isDark, baseStyle),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value, bool isDark, TextStyle baseStyle) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() => _filter = value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? BondhuTokens.primary.withValues(alpha: 0.16) : const Color(0xFFDCFCE7))
                : (isDark ? const Color(0xFF020617) : const Color(0xFFF3F4F6)),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? (isDark ? BondhuTokens.primary : const Color(0xFF22C55E))
                  : (isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB)),
            ),
          ),
          child: Row(
            children: [
              if (value == 'unread' && NotificationService.instance.unreadCount > 0) ...[
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF34D399) : BondhuTokens.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              Text(
                label,
                style: baseStyle.copyWith(
                  color: selected
                      ? (isDark ? const Color(0xFFBBF7D0) : const Color(0xFF166534))
                      : (isDark ? BondhuTokens.textMutedDark : const Color(0xFF4B5563)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark, {String? message}) {
    final t = AppLanguageService.instance.t;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [Color(0xFF0F172A), Color(0xFF1E293B)]
                    : const [Color(0xFFE0F2FE), Color(0xFFDCFCE7)],
              ),
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              size: 40,
              color: isDark ? BondhuTokens.primary : const Color(0xFF10B981),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message ?? t('notifications_empty'),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
            ),
          ),
        ],
      ),
    );
  }

  List<MapEntry<String, List<AppNotification>>> _groupByDay(List<AppNotification> list) {
    final now = DateTime.now();
    String labelFor(DateTime t) {
      final diff = now.difference(t);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return 'This week';
      return 'Earlier';
    }

    final map = <String, List<AppNotification>>{};
    for (final n in list) {
      final label = labelFor(n.time);
      map.putIfAbsent(label, () => []).add(n);
    }

    // Preserve chronological order within each group (list is already newest-first).
    return map.entries.toList();
  }

  List<AppNotification> _applyFilter(List<AppNotification> list) {
    switch (_filter) {
      case 'unread':
        return list.where((n) => !n.read).toList();
      case 'messages':
        return list.where((n) => n.type == 'message').toList();
      case 'social':
        return list
            .where((n) =>
                n.type == 'like' ||
                n.type == 'comment' ||
                n.type == 'follow' ||
                n.type == 'story_view')
            .toList();
      case 'system':
        return list.where((n) => n.type == 'system').toList();
      case 'all':
      default:
        return list;
    }
  }

  Widget _buildNotificationTile(AppNotification n, bool isDark) {
    final t = AppLanguageService.instance.t;
    IconData icon;
    Color accent;
    switch (n.type) {
      case 'message':
        icon = Icons.chat_bubble_outline_rounded;
        accent = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0EA5E9);
        break;
      case 'like':
        icon = Icons.favorite_border_rounded;
        accent = isDark ? const Color(0xFFF97373) : const Color(0xFFEF4444);
        break;
      case 'comment':
        icon = Icons.mode_comment_outlined;
        accent = isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B);
        break;
      case 'follow':
        icon = Icons.person_add_alt_1_rounded;
        accent = isDark ? const Color(0xFF4ADE80) : const Color(0xFF22C55E);
        break;
      case 'story_view':
        icon = Icons.history_edu_rounded;
        accent = isDark ? const Color(0xFFA855F7) : const Color(0xFF8B5CF6);
        break;
      default:
        icon = Icons.notifications_none_rounded;
        accent = isDark ? BondhuTokens.primary : const Color(0xFF10B981);
        break;
    }

    String timeAgo() {
      final now = DateTime.now();
      final diff = now.difference(n.time);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${n.time.day}/${n.time.month}';
    }

    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF991B1B) : const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
        ),
      ),
      onDismissed: (_) {
        NotificationService.instance.remove(n.id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: n.read
              ? (isDark ? const Color(0xFF020617) : Colors.white)
              : (isDark ? const Color(0xFF020617) : const Color(0xFFF0FDF4)),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: n.read
                ? (isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB))
                : (isDark ? BondhuTokens.primary.withValues(alpha: 0.4) : const Color(0xFF86EFAC)),
          ),
          boxShadow: [
            if (!n.read)
              BoxShadow(
                color: isDark
                    ? BondhuTokens.primary.withValues(alpha: 0.25)
                    : BondhuTokens.primary.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 10),
              )
            else
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            NotificationService.instance.markRead(n.id);
            widget.onNotificationTap(n);
            setState(() {});
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: 0.2),
                      accent,
                    ],
                  ),
                ),
                child: n.avatarUrl != null && n.avatarUrl!.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          n.avatarUrl!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: n.read ? FontWeight.w600 : FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF111827),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeAgo(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        height: 1.35,
                        color: isDark ? BondhuTokens.textMutedDark : const Color(0xFF4B5563),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (!n.read)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        if (n.type == 'message')
                          _miniTag(t('notifications_type_message'), isDark)
                        else if (n.type == 'system')
                          _miniTag(t('notifications_type_system'), isDark)
                        else
                          _miniTag(t('notifications_type_social'), isDark),
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

  Widget _miniTag(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF020617) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: isDark ? BondhuTokens.textMutedDark : const Color(0xFF6B7280),
        ),
      ),
    );
  }
}

