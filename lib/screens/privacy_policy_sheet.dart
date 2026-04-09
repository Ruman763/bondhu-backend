import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design_tokens.dart';
import '../services/app_language_service.dart';

/// Shows the Bondhu app Privacy Policy in a modal bottom sheet.
/// Call from Wallet (More) or Settings (Privacy & Security).
void showBondhuPrivacyPolicy(BuildContext context, bool isDark) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _BondhuPrivacyPolicySheet(isDark: isDark),
  );
}

class _BondhuPrivacyPolicySheet extends StatelessWidget {
  const _BondhuPrivacyPolicySheet({required this.isDark});

  final bool isDark;

  static const String _policyText = '''
1. Introduction
Bondhu ("we", "our", or "the app") is a chat‑first social app that offers private messaging, audience‑based profiles, a social feed, and wallet features. This Privacy Policy explains what data we collect, how we use it, and your rights. By using Bondhu, you agree to this policy.

2. Data We Collect
• Account & profile: Email, name, profile photo (avatar), bio, location, and (if you use the feature) a list of contacts. This is stored so your profile and contacts sync across devices.
• Audience profiles: Optional “Default / Personal / Work” profile variants (name, bio, avatar) so different people can see different versions of your profile, depending on which folder a chat is in.
• Chat: Private (1:1) chat messages, images, files, voice notes, and call‑related metadata (for example: that a call happened, its time and duration). Message content is end‑to‑end encrypted. We do not store your private message content on our servers.
• Chat notes and saved items: Per‑chat notes, message pins, and saved messages you create inside the app. These are stored locally on your device (for example using secure storage / preferences) so only you can see them.
• Feed: Posts and stories you create (text, images, video), likes, comments, saves, and view/like data so the feed works correctly.
• Wallet: Transaction history and balance information used to run the wallet features in the app (where available).
• Presence & delivery: Information like when you were last online, whether you have read a message (read receipts), and whether you are typing. You can control most of these signals from Settings → Privacy & Security.
• Technical: Session data for login, basic device information (such as OS version), and local preferences (e.g. theme, language, vibration, notification style) to keep the app working and improve your experience.
• Device storage: Your private chat messages, chat list, encryption keys, chat notes, and some preferences are stored only on the device you use. We do not automatically back up this data to our servers. If you lose the device or clear app data, this local history and keys cannot be restored.

3. How We Use Your Data
We use your data to:
• Create and manage your account and profile (including audience‑based profiles).
• Sync your contacts and basic profile information across devices you log into.
• Deliver private chats, calls, and media in real time. Private message content is end‑to‑end encrypted and not readable by us.
• Run the social parts of the app (feed, posts, stories, likes, comments, followers / following).
• Operate any wallet or payment‑related features where they are enabled.
• Show basic insights such as follower counts or story views.
• Understand app stability and performance (for example, crash/error logs) so we can fix bugs.
• Respond when you contact Help & Support or reach out via email or social channels.

We do not sell your personal data to third parties.

4. Where Your Data Is Stored
• Account, profile (including audience profiles), feed, followers / following, and wallet‑related data are stored with our backend and database provider (Supabase).
• Private chat messages, encryption keys, and local notes are stored only on your device.
• Real‑time chat is delivered via our messaging server as encrypted content only. We route messages but cannot read the encrypted content.

5. Security & Encryption
We use industry‑standard practices to protect your data. All private (1:1) communication is end‑to‑end encrypted: text messages, images, files, voice messages, and calls. Only you and the recipient can read or access the content — we cannot, and we do not store it on our servers. No system is 100% secure; we recommend keeping your password safe and logging out on shared devices.

6. Your Choices
You can:
• Update or delete profile information in Settings.
• Choose which audience (Default / Personal / Work) a chat sees from the chat info screen.
• Control privacy options like read receipts, last seen, online status, and typing indicators from Settings → Privacy & Security.
• Delete chats, messages, and chat notes from inside the app (this does not delete content other people have saved or posted in the feed).
• Block users and change your password from Settings → Privacy & Security.
• Decide what you post to the feed and when to remove your own posts or stories.

Feedback and support requests are voluntary. You may contact us to ask about or delete your account and associated data (subject to legal and technical limitations).

7. Children
Bondhu is not intended for users under 13. We do not knowingly collect data from children under 13.

8. Changes
We may update this Privacy Policy from time to time. Continued use of the app after changes means you accept the updated policy.

9. Contact Us
For privacy questions, feedback, or to request access/deletion of your data, you can reach the founder through any of these channels:
• Email: mdrumanislam763@gmail.com
• Facebook: https://www.facebook.com/share/1CNZrs6RuV/?mibextid=wwXIfr
• Instagram: https://www.instagram.com/ruman_351
You can also use Help & Support inside the app.

Last updated: March 2026.
''';

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * (isWide ? 0.85 : 0.9)),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : Colors.white,
        borderRadius: BorderRadius.vertical(top: const Radius.circular(24)),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : BondhuTokens.borderLight),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: BondhuTokens.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.shield_outlined, color: BondhuTokens.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLanguageService.instance.t('privacy_policy'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            color: isDark ? Colors.white.withValues(alpha: 0.06) : BondhuTokens.borderLight,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.amber.withValues(alpha: 0.12) : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.6)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Beta launch — for testing only',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.amber.shade200 : Colors.amber.shade800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'This app is in beta. Use for testing purposes only.',
                          style: TextStyle(fontSize: 11, color: isDark ? Colors.amber.shade300 : Colors.amber.shade700),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _policyText,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      height: 1.6,
                      color: isDark ? BondhuTokens.textMutedDark : const Color(0xFF4B5563),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF9FAFB),
              border: Border(top: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.06) : BondhuTokens.borderLight)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: BondhuTokens.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(AppLanguageService.instance.t('understood'), style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
