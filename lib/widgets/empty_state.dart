import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design_tokens.dart';

/// Reusable empty state for lists/screens. Bondhu design.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight;
    final iconColor = isDark ? BondhuTokens.textMutedDark.withValues(alpha: 0.6) : BondhuTokens.textMutedLight.withValues(alpha: 0.8);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? Icons.inbox_outlined,
              size: 64,
              color: iconColor,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: textColor,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: BondhuTokens.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  actionLabel!,
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Centered loading indicator with optional label. Bondhu styling.
class LoadingState extends StatelessWidget {
  const LoadingState({
    super.key,
    this.message,
  });

  final String? message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: BondhuTokens.loadingSpinnerSize,
            height: BondhuTokens.loadingSpinnerSize,
            child: CircularProgressIndicator(
              strokeWidth: BondhuTokens.loadingSpinnerBorder,
              valueColor: const AlwaysStoppedAnimation<Color>(BondhuTokens.primary),
              backgroundColor: isDark ? BondhuTokens.surfaceDarkHover : BondhuTokens.borderLight,
            ),
          ),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
