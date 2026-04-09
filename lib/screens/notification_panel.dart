import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design_tokens.dart';
import '../services/notification_service.dart';

/// Full-screen or modal panel showing the list of in-app notifications.
class NotificationPanel extends StatelessWidget {
  const NotificationPanel({
    super.key,
    required this.notifications,
    required this.isDark,
    required this.onMarkAllRead,
    required this.onTap,
    required this.onClose,
  });

  final List<AppNotification> notifications;
  final bool isDark;
  final VoidCallback onMarkAllRead;
  final ValueChanged<AppNotification> onTap;
  final VoidCallback onClose;

  static String _timeAgo(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(
                    'Notifications',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                  const Spacer(),
                  if (notifications.any((n) => !n.read))
                    TextButton(
                      onPressed: onMarkAllRead,
                      child: Text(
                        'Mark all read',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: BondhuTokens.primary,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(Icons.close, color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight),
            Expanded(
              child: notifications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_none,
                            size: 64,
                            color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No notifications yet',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: notifications.length,
                      itemBuilder: (context, i) {
                        final n = notifications[i];
                        return Material(
                          key: ValueKey(n.id),
                          color: n.read
                              ? Colors.transparent
                              : (isDark ? Colors.white.withValues(alpha: 0.03) : BondhuTokens.surfaceLight.withValues(alpha: 0.6)),
                          child: InkWell(
                            onTap: () {
                              onTap(n);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.borderLight,
                                    backgroundImage: n.avatarUrl != null && n.avatarUrl!.isNotEmpty
                                        ? NetworkImage(n.avatarUrl!)
                                        : null,
                                    child: n.avatarUrl == null || n.avatarUrl!.isEmpty
                                        ? Icon(
                                            n.type == 'message' ? Icons.chat_bubble_outline : Icons.notifications_outlined,
                                            size: 22,
                                            color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          n.title,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 14,
                                            fontWeight: n.read ? FontWeight.w500 : FontWeight.w700,
                                            color: isDark ? Colors.white : const Color(0xFF111827),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          n.body,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13,
                                            color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _timeAgo(n.time),
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
