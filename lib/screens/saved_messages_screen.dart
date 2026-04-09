import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/chat_service.dart';
import '../services/starred_message_service.dart';

/// Saved (starred) messages with search and labels. Better than WhatsApp: labels (Important, To do, Later) and search.
class SavedMessagesScreen extends StatefulWidget {
  const SavedMessagesScreen({
    super.key,
    required this.chatService,
    required this.onOpenChat,
    required this.isDark,
  });

  final ChatService chatService;
  final void Function(String chatId) onOpenChat;
  final bool isDark;

  @override
  State<SavedMessagesScreen> createState() => _SavedMessagesScreenState();
}

class _SavedMessagesScreenState extends State<SavedMessagesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _labelFilter;

  @override
  void initState() {
    super.initState();
    StarredMessageService.instance.load();
    _searchController.addListener(() {
      if (mounted) setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _chatName(String chatId) {
    for (final c in widget.chatService.chats) {
      if (c.id.trim().toLowerCase() == chatId.trim().toLowerCase()) return c.name;
    }
    return ChatService.formatName(chatId);
  }

  String _messagePreview(String chatId, String messageId) {
    final list = widget.chatService.getMessages(chatId);
    ChatMessage? msg;
    for (final m in list) {
      if (m.id == messageId) {
        msg = m;
        break;
      }
    }
    if (msg == null) return '…';
    if (msg.type == 'image') return '🖼 ${AppLanguageService.instance.t('image')}';
    if (msg.type == 'audio') return '🎤 Voice message';
    if (msg.type == 'file') return '📎 File';
    final t = msg.text;
    return t.length > 80 ? '${t.substring(0, 80)}…' : t;
  }

  bool _matches(StarredEntry e, String chatName, String preview) {
    if (_labelFilter != null && (_labelFilter!.isNotEmpty)) {
      if ((e.label ?? '') != _labelFilter) return false;
    }
    if (_query.isEmpty) return true;
    return chatName.toLowerCase().contains(_query) ||
        preview.toLowerCase().contains(_query) ||
        (e.label?.toLowerCase().contains(_query) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final surface = widget.isDark ? const Color(0xFF18181B) : Colors.white;
    final textPrimary = widget.isDark ? Colors.white : const Color(0xFF111827);
    final textMuted = widget.isDark ? const Color(0xFF71717A) : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: widget.isDark ? BondhuTokens.bgDark : const Color(0xFFF4F4F6),
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          AppLanguageService.instance.t('saved_messages'),
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: AppLanguageService.instance.t('type_to_search'),
                hintStyle: TextStyle(color: textMuted, fontSize: 14),
                prefixIcon: Icon(Icons.search_rounded, color: textMuted, size: 22),
                filled: true,
                fillColor: widget.isDark ? const Color(0xFF27272A) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: TextStyle(color: textPrimary, fontSize: 14),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(
                    label: AppLanguageService.instance.t('all'),
                    value: null,
                    isDark: widget.isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: AppLanguageService.instance.t('label_important'),
                    value: 'Important',
                    isDark: widget.isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: AppLanguageService.instance.t('label_todo'),
                    value: 'To do',
                    isDark: widget.isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: AppLanguageService.instance.t('label_later'),
                    value: 'Later',
                    isDark: widget.isDark,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: StarredMessageService.instance.version,
              builder: (context, version, child) {
                final entries = StarredMessageService.instance.all;
                final filtered = entries.where((e) {
                  final name = _chatName(e.chatId);
                  final preview = _messagePreview(e.chatId, e.messageId);
                  return _matches(e, name, preview);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      entries.isEmpty
                          ? AppLanguageService.instance.t('no_matches')
                          : AppLanguageService.instance.t('no_matches'),
                      style: TextStyle(fontSize: 14, color: textMuted),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 4),
                  itemBuilder: (context, i) {
                    final e = filtered[i];
                    final chatName = _chatName(e.chatId);
                    final preview = _messagePreview(e.chatId, e.messageId);
                    return Material(
                      color: surface,
                      child: InkWell(
                        onTap: () {
                          widget.onOpenChat(e.chatId);
                          Navigator.of(context).pop();
                        },
                        onLongPress: () async {
                          final remove = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: surface,
                              title: Text(
                                AppLanguageService.instance.t('unstar_message'),
                                style: TextStyle(color: textPrimary),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(AppLanguageService.instance.t('cancel')),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(
                                    AppLanguageService.instance.t('unstar_message'),
                                    style: const TextStyle(color: Color(0xFFDC2626)),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (remove == true && mounted) {
                            await StarredMessageService.instance.remove(e.chatId, e.messageId);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.bookmark_rounded,
                                size: 20,
                                color: BondhuTokens.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      chatName,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      preview,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: textMuted,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (e.label != null && e.label!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: BondhuTokens.primary.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          e.label!,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: BondhuTokens.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required String? value,
    required bool isDark,
  }) {
    final selected = _labelFilter == value;
    final bg = selected
        ? BondhuTokens.primary.withValues(alpha: 0.12)
        : (isDark ? const Color(0xFF27272A) : Colors.white);
    final border = selected
        ? BondhuTokens.primary
        : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFE5E7EB));
    final textColor = selected
        ? BondhuTokens.primary
        : (isDark ? Colors.white : const Color(0xFF111827));
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        setState(() {
          _labelFilter = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
