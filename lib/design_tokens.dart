import 'package:flutter/material.dart';

/// Pixel-perfect design tokens from Bondhu Vue app (Tailwind + style.css).
/// Tailwind: 1 unit = 4px. Arbitrary values from Vue: w-[88px] etc.
class BondhuTokens {
  BondhuTokens._();

  /// Breakpoint for mobile-first compact UI (small phones).
  static const double breakpointMobile = 380;
  /// Breakpoint for tablet/desktop.
  static const double breakpointTablet = 768;

  /// True when width < 768 (mobile).
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < breakpointTablet;
  /// True when width < 380 (small phone) for extra compact layout.
  static bool isSmallPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < breakpointMobile;

  /// Scale factor for mobile: 1.0 on tablet+, 0.9 on phone, 0.82 on small phone.
  static double scale(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= breakpointTablet) return 1.0;
    if (w >= breakpointMobile) return 0.9;
    return 0.82;
  }

  /// Responsive value: [mobile, tablet+].
  static T responsive<T>(BuildContext context, T mobile, T tablet) =>
      isMobile(context) ? mobile : tablet;
  /// Three-way: [smallPhone, mobile, tablet+].
  static T responsive3<T>(BuildContext context, T small, T mobile, T tablet) {
    if (!isMobile(context)) return tablet;
    return isSmallPhone(context) ? small : mobile;
  }

  // ---------- Colors (exact hex from Vue) ----------
  static const Color primary = Color(0xFF00C896);
  static const Color primaryDark = Color(0xFF00A87E);
  static const Color primaryLight = Color(0xFF00E0A8);

  static const Color bgLight = Color(0xFFF4F4F5);       // gray-100, --body-bg
  static const Color bgDark = Color(0xFF000000);        // true black for OLED (saves battery)
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF0D0D0D);  // near-black, elevated surfaces
  static const Color surfaceDarkAlt = Color(0xFF0A0A0A);
  static const Color surfaceDarkHover = Color(0xFF1A1A1A);
  static const Color surfaceDarkCard = Color(0xFF121212);  // cards slightly above black

  static const Color textPrimaryLight = Color(0xFF18181B);
  static const Color textPrimaryDark = Color(0xFFF1F5F9);  // slate-100 (softer than pure white)
  static const Color textMutedLight = Color(0xFF71717A);
  static const Color textMutedDark = Color(0xFF94A3B8);    // slate-400
  static const Color textMutedDarkAlt = Color(0xFF64748B); // slate-500

  static const Color borderLight = Color(0xFFE5E5E5);    // gray-200
  static const Color borderDark = Color(0xFF1F1F1F);     // subtle on OLED
  static const Color borderDarkSoft = Color(0x1AFFFFFF); // white/10

  static const Color inputBgLight = Color(0xFFF4F4F5);
  static const Color inputBgDark = Color(0xFF0D0D0D);
  static const Color authContainerDark = Color(0xFF121212);

  // ---------- Spacing (px) ----------
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space10 = 40;
  static const double space12 = 48;

  // ---------- Sidebar (App.vue: fixed left-4 top-4 bottom-4 w-[88px] rounded-3xl py-8 px-3) ----------
  static const double sidebarLeft = 16;      // left-4 = 16px
  static const double sidebarTop = 16;
  static const double sidebarBottom = 16;
  static const double sidebarWidth = 88;     // w-[88px]
  static const double sidebarRadius = 24;    // rounded-3xl
  static const double sidebarPaddingY = 32;  // py-8
  static const double sidebarPaddingX = 12;  // px-3 → content width = 88-24 = 64
  static const double sidebarLogoSize = 48;  // w-12 h-12
  static const double sidebarLogoRadius = 16; // rounded-2xl
  static const double sidebarLogoMarginBottom = 40; // mb-10
  static const double sidebarNavGap = 24;    // gap-6
  static const double sidebarNavItemSize = 64; // w-full aspect-square in 64px content area
  static const double sidebarAvatarSize = 48; // w-12 h-12
  static const double sidebarAvatarBorder = 2;

  // ---------- Main content ----------
  static const double mainContentPaddingLeftDesktop = 120; // md:pl-[120px] = 88 + 32
  static const double mainContentPaddingBottomMobile = 80; // pb-20

  // ---------- Bottom nav (h-16, 4 items) ----------
  static const double bottomNavHeight = 64;
  static const double bottomNavAvatarSize = 28; // w-7 h-7

  // ---------- Auth (AuthScreen.vue + style.css) ----------
  static const double authContainerMaxWidth = 800;
  static const double authContainerMinHeight = 550;
  static const double authContainerRadius = 24;
  static const double authFormPaddingHorizontal = 50;
  static const double authLogoSize = 56;     // w-14 h-14
  static const double authLogoRadius = 16;
  static const double authLogoMarginBottom = 8;
  static const double authSocialButtonSize = 44;
  static const double authSocialMargin = 20;
  static const double authSocialGap = 8;
  static const double authInputPaddingV = 14;
  static const double authInputPaddingH = 18;
  static const double authInputMargin = 8;
  static const double authInputRadius = 12;
  static const double authButtonPaddingV = 14;
  static const double authButtonPaddingH = 50;
  static const double authButtonRadius = 30;
  static const double authOverlayPaddingH = 40;

  // ---------- Typography ----------
  static const double fontSize9 = 9;
  static const double fontSize10 = 10;
  static const double fontSize11 = 11;
  static const double fontSize12 = 12;
  static const double fontSize13 = 13;
  static const double fontSize14 = 14;
  static const double fontSizeBase = 16;
  static const double fontSizeLg = 18;
  static const double fontSizeXl = 20;
  static const double fontSize2xl = 24;
  static const double fontSize3xl = 30;

  // ---------- Loading spinner ----------
  static const double loadingSpinnerSize = 48;
  static const double loadingSpinnerBorder = 4;

  // ---------- Wallet (WalletView.vue: exact px) ----------
  static const double walletColumnWidthDesktop = 480; // md:w-[480px]
  static const double walletHeaderPaddingH = 20;     // pl-5 pr-5
  static const double walletHeaderPaddingL = 20;     // pl-5
  static const double walletHeaderPaddingR = 20;     // pr-5
  static const double walletHeaderPaddingRDesktop = 48; // md:pr-12
  static const double walletHeaderPaddingTop = 24;   // pt-6
  static const double walletHeaderPaddingBottom = 8; // pb-2
  static const double walletHeaderMarginBottom = 24; // mb-6
  static const double walletHeaderButtonSize = 40;   // w-10 h-10
  static const double walletContentPaddingH = 20;   // px-5
  static const double walletContentMarginBottom = 16; // mb-4
  static const double walletContentGap = 24;        // space-y-6
  static const double walletContentPaddingBottomMobile = 96; // pb-24
  static const double walletComingSoonRadius = 16;   // rounded-2xl
  static const double walletComingSoonPadding = 16; // px-4 py-4
  static const double walletComingSoonMarginBottom = 16; // mb-4
  static const double walletCardHeight = 220;       // h-[220px]
  static const double walletCardRadius = 32;        // rounded-[32px]
  static const double walletCardPadding = 24;       // p-6
  static const double walletSectionTitleMarginBottom = 16; // mb-4
  static const double walletSectionTitleMarginLeft = 4; // ml-1
  static const double walletServicesGridGap = 12;   // gap-3
  static const double walletServicesGridGapDesktop = 16; // md:gap-4
  static const double walletServiceIconSize = 56;    // w-14 h-14
  static const double walletServiceIconRadius = 20; // rounded-[20px]
  static const double walletTransactionsRadius = 24; // rounded-[24px]
  static const double walletTransactionsPadding = 8; // p-2
  static const double walletTransactionsMinHeight = 150; // min-h-[150px]
  static const double walletTransactionItemRadius = 20; // rounded-[20px]
  static const double walletTransactionItemPadding = 12; // p-3
  static const double walletMoreRowPadding = 16;    // p-4
  static const double walletMoreIconSize = 32;      // w-8 h-8
  static const double walletFabSize = 56;           // w-[56px] h-[56px]
  static const double walletFabBottom = 32;         // bottom-8
  static const double walletFabRight = 32;          // right-8
  static const double walletFabRightDesktop = 48;   // md:right-12

  // ---------- Feed (FeedView.vue: exact px) ----------
  static const double feedColumnWidthDesktop = 480;  // md:w-[480px]
  static const double feedHeaderPaddingH = 20;       // px-5
  static const double feedHeaderPaddingV = 16;       // py-4
  static const double feedHeaderRowHeight = 40;     // h-10
  static const double feedSearchButtonSize = 36;    // w-9 h-9
  static const double feedSearchMarginTop = 12;     // mt-3
  static const double feedSearchInputPaddingH = 16;
  static const double feedSearchInputPaddingV = 8;
  static const double feedSearchInputRadius = 12;   // rounded-xl
  static const double feedStoriesSize = 64;         // w-16 h-16 (legacy circle)
  static const double feedStoryBoxWidth = 68;       // compact story card
  static const double feedStoryBoxHeight = 102;    // ~2:3 ratio
  static const double feedStoryBoxRadius = 10;     // rounded-lg
  static const double feedStoryBoxAvatarSize = 22; // circle inside box
  static const double feedStoriesGap = 16;          // gap-4
  static const double feedStoriesPaddingH = 16;     // px-4
  static const double feedStoriesPaddingV = 8;      // py-2
  static const double feedStoriesLabelWidth = 56;   // w-14 for name
  static const double feedCreatePostMarginH = 16;   // mx-4
  static const double feedCreatePostMarginTop = 16; // mt-4
  static const double feedCreatePostMarginBottom = 24; // mb-6
  static const double feedCreatePostRadius = 16;    // rounded-2xl
  static const double feedCreatePostPadding = 12;   // p-3 mobile
  static const double feedCreatePostPaddingDesktop = 16; // md:p-4
  static const double feedCreatePostAvatarSize = 36; // w-9 h-9
  static const double feedCreatePostGap = 10;       // gap-2.5
  static const double feedCreatePostStatusDotSize = 10; // w-2.5 h-2.5
  static const double feedPostListGap = 32;         // space-y-8
  static const double feedPostItemPaddingBottom = 24; // pb-6
  static const double feedPostItemPaddingH = 16;    // px-4
  static const double feedPostItemMarginBottom = 12; // mb-3
  static const double feedPostAvatarSize = 40;      // w-10 h-10
  static const double feedPostAvatarGap = 12;       // gap-3
  static const double feedPostMediaMaxHeight = 500; // max-h-[500px]
  static const double feedPostActionGap = 20;       // gap-5
  static const double feedRightPanelTextSize = 120; // text-[120px]

  // ---------- Feed Profile tab (FeedView.vue currentTab === 'profile') ----------
  static const double feedProfilePaddingH = 20;     // px-5
  static const double feedProfilePaddingTop = 16;  // pt-4
  static const double feedProfilePaddingBottom = 24; // pb-6
  static const double feedProfileAvatarSize = 80;   // w-20 h-20
  static const double feedProfileAvatarBorder = 2;  // border-2 border-[#00C896]
  static const double feedProfileStatsGap = 24;     // gap-6
  static const double feedProfileNameSize = 18;     // text-lg
  static const double feedProfileBioMarginTop = 4;  // mt-1
  static const double feedProfileLocationMarginTop = 8; // mt-2
  static const double feedProfileButtonsMarginBottom = 20; // mb-5
  static const double feedProfileButtonsGap = 8;   // gap-2
  static const double feedProfileTabBorderTop = 8;  // mt-2
  static const double feedProfileGridGap = 2;      // gap-0.5
  static const double feedProfileGridPaddingBottom = 40; // pb-10
  static const double feedProfileEmptyPaddingVertical = 48; // py-12

  // ---------- Chat (ChatView / App.vue search) ----------
  static const double chatSearchHeight = 44;
  static const double chatSearchRadius = 14;
  static const double chatAvatarSize = 56;       // list row ~ w-11 h-11 = 44, use 56 for prominence
  static const double chatRowPadding = 12;
  static const double chatRowRadius = 16;

  // ---------- Website embed (flutter-view) ----------
  /// Matches website embed: position absolute; inset: 0; width: 438px; height: 659px
  static const double flutterViewWidth = 438;
  static const double flutterViewHeight = 659;

  // ---------- Motion (modern, consistent) ----------
  static const Duration motionFast = Duration(milliseconds: 150);
  static const Duration motionNormal = Duration(milliseconds: 250);
  static const Duration motionSlow = Duration(milliseconds: 400);
  static const Curve motionEase = Curves.easeOutCubic;
  static const Curve motionEmphasized = Curves.easeInOutCubic;

  // ---------- Radius scale (modern rounded UI) ----------
  static const double radiusXs = 6;
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;
  static const double radiusXl = 24;
  static const double radius2xl = 28;
  static const double radiusFull = 9999;

  // ---------- Elevation (subtle depth) ----------
  static const double elevationSm = 1;
  static const double elevationMd = 2;
  static const double elevationLg = 4;
  static const double elevationXl = 8;

  // ---------- Shadows ----------
  static List<BoxShadow> get sidebarShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.12),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
  static List<BoxShadow> get logoGlow => [
    BoxShadow(
      color: primary.withValues(alpha: 0.4),
      blurRadius: 15,
      spreadRadius: 0,
    ),
  ];
  static List<BoxShadow> get authContainerShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.15),
      blurRadius: 50,
      offset: const Offset(0, 20),
    ),
  ];
  static List<BoxShadow> get authButtonShadow => [
    BoxShadow(
      color: primary.withValues(alpha: 0.4),
      blurRadius: 15,
      offset: const Offset(0, 4),
    ),
  ];
  static List<BoxShadow> get fabFeedbackShadow => [
    BoxShadow(
      color: Colors.orange.withValues(alpha: 0.4),
      blurRadius: 25,
      offset: const Offset(0, 8),
    ),
  ];

  /// Modern card shadow: subtle lift (light mode).
  static List<BoxShadow> get cardShadowLight => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 12,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.02),
      blurRadius: 6,
      offset: const Offset(0, 1),
    ),
  ];

  /// Modern card shadow: subtle lift (dark mode).
  static List<BoxShadow> get cardShadowDark => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  /// Surface color for current brightness (for consistent backgrounds).
  static Color surface(BuildContext context) =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark ? surfaceDarkCard : surfaceLight;
  static Color textMuted(BuildContext context) =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark ? textMutedDark : textMutedLight;
  static Color textPrimary(BuildContext context) =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark ? textPrimaryDark : textPrimaryLight;
}
