import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_animations.dart';
import '../design_tokens.dart';
import '../services/app_language_service.dart';
import 'privacy_policy_sheet.dart';

class WalletView extends StatelessWidget {
  const WalletView({
    super.key,
    required this.userName,
    required this.isDark,
    this.onNavigateToChat,
  });

  final String? userName;
  final bool isDark;
  final VoidCallback? onNavigateToChat;

  static List<(IconData, String, Color)> _services(AppLanguageService l10n) => [
        (Icons.bolt, l10n.t('wallet_recharge'), BondhuTokens.primary),
        (Icons.send, l10n.t('wallet_send'), Colors.blue),
        (Icons.qr_code_scanner, l10n.t('wallet_scan'), const Color(0xFFE5E5E5)),
        (Icons.sports_esports, l10n.t('wallet_games'), Colors.purple),
        (Icons.receipt_long, l10n.t('wallet_pay_bill'), Colors.amber),
        (Icons.train, l10n.t('wallet_train'), Colors.orange),
        (Icons.hotel, l10n.t('wallet_hotel'), Colors.deepOrange),
        (Icons.shopping_bag, l10n.t('wallet_shop'), Colors.pink),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLanguageService.instance;
    final services = _services(l10n);
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 1024;

    final contentPadH = BondhuTokens.walletContentPaddingH;
    final contentPadRight = isWide ? (contentPadH + 8) : contentPadH;
    final fabRight = BondhuTokens.responsive(context, BondhuTokens.walletFabRight, BondhuTokens.walletFabRightDesktop);
    final fabBottom = BondhuTokens.walletFabBottom;
    final bottomPad = isWide ? BondhuTokens.space4 : BondhuTokens.mainContentPaddingBottomMobile + 24;

    final scrollContent = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        contentPadH,
        BondhuTokens.walletHeaderPaddingTop,
        contentPadRight,
        bottomPad,
      ),
      child: _buildWalletColumn(context, l10n, services, isWide),
    );

    final fabButton = Positioned(
      right: fabRight,
      bottom: fabBottom,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (onNavigateToChat != null) {
              onNavigateToChat!();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLanguageService.instance.t('open_chat_to_message')), behavior: SnackBarBehavior.floating),
              );
            }
          },
          borderRadius: BorderRadius.circular(BondhuTokens.walletFabSize / 2),
          child: Container(
            width: BondhuTokens.walletFabSize,
            height: BondhuTokens.walletFabSize,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFB923C), Color(0xFFEAB308)],
              ),
              shape: BoxShape.circle,
              boxShadow: BondhuTokens.fabFeedbackShadow,
            ),
            child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF0A0A0A), size: 20),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
      body: SafeArea(
        child: isWide
            ? Row(
                children: [
                  SizedBox(
                    width: BondhuTokens.feedColumnWidthDesktop,
                    child: Stack(
                      children: [
                        scrollContent,
                        fabButton,
                      ],
                    ),
                  ),
                  Expanded(child: _buildWalletRightPanel(context)),
                ],
              )
            : Stack(
                children: [
                  scrollContent,
                  fabButton,
                ],
              ),
      ),
    );
  }

  Column _buildWalletColumn(
    BuildContext context,
    AppLanguageService l10n,
    List<(IconData, String, Color)> services,
    bool isWide,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        FadeSlideIn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.t('hello'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: BondhuTokens.fontSize10,
                  fontWeight: FontWeight.w700,
                  color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                  letterSpacing: 1.2,
                ),
              ),
              SizedBox(height: BondhuTokens.space1),
              Text(
                userName ?? l10n.t('user'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: BondhuTokens.responsive(context, 18.0, 22.0),
                  fontWeight: FontWeight.w800,
                  color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: BondhuTokens.walletContentGap),

        // Coming soon banner
        FadeSlideIn(
          delay: AppAnimations.fast,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            margin: const EdgeInsets.only(bottom: BondhuTokens.walletComingSoonMarginBottom),
            decoration: BoxDecoration(
              color: isDark ? Colors.amber.withValues(alpha: 0.12) : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(BondhuTokens.walletComingSoonRadius),
              border: Border.all(
                color: isDark ? Colors.amber.withValues(alpha: 0.8) : Colors.amber.shade700,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Text(
                  l10n.t('wallet_coming_soon_title'),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.amber.shade200 : Colors.amber.shade800,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.t('wallet_coming_soon_sub'),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.amber.shade300 : Colors.amber.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: BondhuTokens.walletContentGap),

        // Wallet card
        FadeSlideIn(
          delay: const Duration(milliseconds: 150),
          child: Container(
            height: BondhuTokens.walletCardHeight,
            padding: const EdgeInsets.all(BondhuTokens.walletCardPadding),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        const Color(0xFF0F172A),
                        const Color(0xFF1E293B),
                        const Color(0xFF0F172A),
                      ]
                    : [
                        const Color(0xFF334155),
                        const Color(0xFF475569),
                        const Color(0xFF64748B),
                      ],
              ),
              borderRadius: BorderRadius.circular(BondhuTokens.walletCardRadius),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : BondhuTokens.borderLight,
              ),
              boxShadow: [
                BoxShadow(
                  color: BondhuTokens.primary.withValues(alpha: 0.15),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL BALANCE',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white54,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '৳',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: BondhuTokens.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '0',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Wallet — Coming soon',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: Colors.amber.shade300,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 28,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HOLDER',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.white.withValues(alpha: 0.5),
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (userName ?? 'User').toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.credit_card,
                      size: 32,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: BondhuTokens.walletContentGap),

        // Services grid
        Text(
          'Services',
          style: GoogleFonts.plusJakartaSans(
            fontSize: BondhuTokens.fontSize14,
            fontWeight: FontWeight.w700,
            color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
          ),
        ),
        SizedBox(height: BondhuTokens.walletSectionTitleMarginBottom),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          mainAxisSpacing: BondhuTokens.responsive(context, BondhuTokens.walletServicesGridGap, BondhuTokens.walletServicesGridGapDesktop),
          crossAxisSpacing: BondhuTokens.responsive(context, BondhuTokens.walletServicesGridGap, BondhuTokens.walletServicesGridGapDesktop),
          childAspectRatio: 0.9,
          children: services.map((s) {
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${s.$2} ${AppLanguageService.instance.t('coming_soon')}'), behavior: SnackBarBehavior.floating),
                  );
                },
                borderRadius: BorderRadius.circular(BondhuTokens.walletServiceIconRadius),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: BondhuTokens.walletServiceIconSize,
                      height: BondhuTokens.walletServiceIconSize,
                      decoration: BoxDecoration(
                        color: isDark ? BondhuTokens.surfaceDarkAlt : BondhuTokens.surfaceLight,
                        borderRadius: BorderRadius.circular(BondhuTokens.walletServiceIconRadius),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.05) : BondhuTokens.borderLight,
                        ),
                      ),
                      child: Icon(s.$1, size: 26, color: s.$3),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.$2,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        SizedBox(height: BondhuTokens.walletContentGap),
        SizedBox(
          height: isWide ? 140 : 80,
          width: double.infinity,
          child: Center(
            child: Text(
              l10n.t('wallet_select_service_to_start'),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
                color: isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF4B5563),
              ),
            ),
          ),
        ),
        SizedBox(height: BondhuTokens.walletContentGap),

        // Transactions
        Text(
          'Transactions',
          style: GoogleFonts.plusJakartaSans(
            fontSize: BondhuTokens.fontSize14,
            fontWeight: FontWeight.w700,
            color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
          ),
        ),
        SizedBox(height: BondhuTokens.walletSectionTitleMarginBottom),
        Container(
          padding: EdgeInsets.all(BondhuTokens.walletTransactionsPadding),
          decoration: BoxDecoration(
            color: isDark ? BondhuTokens.surfaceDarkAlt : BondhuTokens.surfaceLight,
            borderRadius: BorderRadius.circular(BondhuTokens.walletTransactionsRadius),
            border: Border.all(
              color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight,
            ),
          ),
          constraints: const BoxConstraints(minHeight: BondhuTokens.walletTransactionsMinHeight),
          child: Center(
            child: Text(
              'No transactions yet',
              style: TextStyle(
                fontSize: BondhuTokens.fontSize13,
                color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
              ),
            ),
          ),
        ),
        SizedBox(height: BondhuTokens.walletContentGap),

        // More
        Text(
          'More',
          style: GoogleFonts.plusJakartaSans(
            fontSize: BondhuTokens.fontSize14,
            fontWeight: FontWeight.w700,
            color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
          ),
        ),
        SizedBox(height: BondhuTokens.space3),
        Container(
          decoration: BoxDecoration(
            color: isDark ? BondhuTokens.surfaceDarkAlt : BondhuTokens.surfaceLight,
            borderRadius: BorderRadius.circular(BondhuTokens.walletTransactionsRadius),
            border: Border.all(
              color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight,
            ),
          ),
          child: Column(
            children: [
              _moreRow(
                isDark: isDark,
                icon: Icons.headset_mic,
                label: AppLanguageService.instance.t('help_support'),
                iconColor: Colors.orange,
                onTap: () {
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: isDark ? const Color(0xFF070815) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: LinearGradient(
                                    colors: [
                                      BondhuTokens.primary,
                                      BondhuTokens.primaryDark,
                                    ],
                                  ),
                                ),
                                child: const Icon(Icons.headset_mic_rounded, color: Colors.black, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLanguageService.instance.t('help_support'),
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? Colors.white : const Color(0xFF111827),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Get in touch directly with the founder if you need help or want to share feedback.',
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
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0B1120) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _supportTile(
                                  ctx,
                                  icon: Icons.email_outlined,
                                  label: 'Email',
                                  value: 'mdrumanislam763@gmail.com',
                                  onTap: () async {
                                    final uri = Uri.parse('mailto:mdrumanislam763@gmail.com');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    }
                                  },
                                ),
                                const Divider(height: 1),
                                _supportTile(
                                  ctx,
                                  icon: Icons.facebook,
                                  label: 'Facebook',
                                  value: '@Bondhu / Ruman Islam',
                                  onTap: () async {
                                    final uri = Uri.parse('https://www.facebook.com/share/1CNZrs6RuV/?mibextid=wwXIfr');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    }
                                  },
                                ),
                                const Divider(height: 1),
                                _supportTile(
                                  ctx,
                                  icon: Icons.camera_alt_outlined,
                                  label: 'Instagram',
                                  value: '@ruman_351',
                                  onTap: () async {
                                    final uri = Uri.parse('https://www.instagram.com/ruman_351');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(
                                AppLanguageService.instance.t('ok'),
                                style: GoogleFonts.plusJakartaSans(
                                  color: BondhuTokens.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Divider(
                height: 1,
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
                indent: 16,
                endIndent: 16,
              ),
              _moreRow(
                isDark: isDark,
                icon: Icons.feedback_outlined,
                label: 'Feedback',
                iconColor: const Color(0xFF0EA5E9),
                onTap: () => _openFeedbackComposer(context),
              ),
              Divider(
                height: 1,
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
                indent: 16,
                endIndent: 16,
              ),
              _moreRow(
                isDark: isDark,
                icon: Icons.shield_outlined,
                label: AppLanguageService.instance.t('privacy_policy'),
                iconColor: Colors.purple,
                onTap: () => showBondhuPrivacyPolicy(context, isDark),
              ),
            ],
          ),
        ),
        SizedBox(height: BondhuTokens.space6),
      ],
    );
  }

  /// Right side panel on desktop, visually similar to chat empty-state.
  Widget _buildWalletRightPanel(BuildContext context) {
    const radius = 40.0;
    const overlapLeft = 16.0;
    return Transform.translate(
      offset: const Offset(-overlapLeft, 0),
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(radius)),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? BondhuTokens.bgDark : const Color(0xFFF4F4F5),
            border: Border(
              left: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFE5E7EB),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.9 : 0.15),
                blurRadius: 60,
                offset: const Offset(-30, 0),
              ),
            ],
          ),
          child: IgnorePointer(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? BondhuTokens.surfaceDark : const Color(0xFFE5E7EB),
              ),
              child: Opacity(
                opacity: isDark ? 0.18 : 0.55,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppLanguageService.instance.t('wallet'),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                          color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLanguageService.instance.t('wallet_select_service_to_start'),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _moreRow({
    required bool isDark,
    required IconData icon,
    required String label,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                width: BondhuTokens.walletMoreIconSize,
                height: BondhuTokens.walletMoreIconSize,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Icon(icon, size: BondhuTokens.fontSizeLg, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: BondhuTokens.fontSize14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFeedbackComposer(BuildContext context) async {
    final feedbackController = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Send Feedback',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: feedbackController,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Write your feedback...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (send != true) return;
    if (!context.mounted) return;
    final text = feedbackController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please write feedback before sending'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!context.mounted) return;
    await _sendFeedbackEmail(context, text);
  }

  Future<void> _sendFeedbackEmail(BuildContext context, String feedbackText) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'mdrumanislam763@gmail.com',
      queryParameters: <String, String>{
        'subject': 'Bondhu app feedback',
        'body': 'User: ${userName ?? 'Unknown'}\n\nFeedback:\n$feedbackText',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open email app'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _supportTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: BondhuTokens.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: BondhuTokens.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? BondhuTokens.textPrimaryDark : const Color(0xFF020617),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

