import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'design_tokens.dart';

class AppTheme {
  /// Dark system overlay for Android: true black bars, light icons.
  static SystemUiOverlayStyle get darkSystemOverlay => SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: BondhuTokens.bgDark,
        systemNavigationBarDividerColor: BondhuTokens.borderDark,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: true,
      );

  /// Light system overlay for Android: light bars, dark icons.
  static SystemUiOverlayStyle get lightSystemOverlay => SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: BondhuTokens.surfaceLight,
        systemNavigationBarDividerColor: BondhuTokens.borderLight,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: true,
      );
  /// On web use Plus Jakarta Sans; on mobile use system font to avoid ANR on low-end devices.
  static String? _cachedWebFont;
  static String? get _fontFamily =>
      kIsWeb ? (_cachedWebFont ??= GoogleFonts.plusJakartaSans().fontFamily ?? 'sans-serif') : null;

  static TextStyle _textStyle({
    required FontWeight fontWeight,
    required Color color,
    required double fontSize,
    double? letterSpacing,
  }) {
    if (kIsWeb) {
      return GoogleFonts.plusJakartaSans(
        fontWeight: fontWeight,
        color: color,
        fontSize: fontSize,
        letterSpacing: letterSpacing ?? 0,
      );
    }
    return TextStyle(
      fontWeight: fontWeight,
      color: color,
      fontSize: fontSize,
      letterSpacing: letterSpacing,
    );
  }

  static ThemeData light(BuildContext context) {
    final colorScheme = ColorScheme.light(
      primary: BondhuTokens.primary,
      onPrimary: Colors.black,
      primaryContainer: BondhuTokens.primaryLight.withValues(alpha: 0.3),
      onPrimaryContainer: BondhuTokens.primaryDark,
      secondary: const Color(0xFF64748B),
      onSecondary: Colors.white,
      surface: BondhuTokens.bgLight,
      onSurface: BondhuTokens.textPrimaryLight,
      surfaceContainerHighest: BondhuTokens.surfaceLight,
      outline: BondhuTokens.borderLight,
      outlineVariant: BondhuTokens.borderLight.withValues(alpha: 0.6),
      shadow: Colors.black26,
      scrim: Colors.black54,
      inverseSurface: BondhuTokens.surfaceDark,
      onInverseSurface: BondhuTokens.textPrimaryDark,
    );
    try {
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: BondhuTokens.bgLight,
        fontFamily: _fontFamily,
        appBarTheme: AppBarTheme(
          backgroundColor: BondhuTokens.surfaceLight,
          foregroundColor: BondhuTokens.textPrimaryLight,
          elevation: 0,
          scrolledUnderElevation: 1,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: _textStyle(
            fontWeight: FontWeight.w700,
            color: BondhuTokens.textPrimaryLight,
            fontSize: BondhuTokens.fontSizeLg,
          ),
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
        cardTheme: CardThemeData(
          color: BondhuTokens.surfaceLight,
          elevation: 0,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BondhuTokens.radiusXl),
            side: BorderSide(color: BondhuTokens.borderLight.withValues(alpha: 0.6)),
          ),
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: BondhuTokens.primary,
            foregroundColor: Colors.black,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: BondhuTokens.authButtonPaddingH,
              vertical: BondhuTokens.authButtonPaddingV,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BondhuTokens.radiusFull),
            ),
            textStyle: _textStyle(
              fontSize: BondhuTokens.fontSize14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Colors.black,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: BondhuTokens.inputBgLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BondhuTokens.radiusMd),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BondhuTokens.radiusMd),
            borderSide: BorderSide(color: BondhuTokens.borderLight.withValues(alpha: 0.6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BondhuTokens.radiusMd),
            borderSide: const BorderSide(color: BondhuTokens.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: BondhuTokens.authInputPaddingH,
            vertical: BondhuTokens.authInputPaddingV,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BondhuTokens.radiusMd)),
          backgroundColor: BondhuTokens.textPrimaryLight,
          contentTextStyle: _textStyle(fontWeight: FontWeight.normal, color: BondhuTokens.surfaceLight, fontSize: 14),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: BondhuTokens.surfaceLight,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(BondhuTokens.radius2xl)),
          ),
          showDragHandle: true,
          dragHandleColor: BondhuTokens.borderLight,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: OpenUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      );
    } catch (_) {
      return ThemeData(useMaterial3: true, colorScheme: colorScheme, scaffoldBackgroundColor: BondhuTokens.bgLight);
    }
  }

  static ThemeData dark(BuildContext context) {
    final colorScheme = ColorScheme.dark(
      primary: BondhuTokens.primary,
      onPrimary: Colors.black,
      primaryContainer: BondhuTokens.primaryDark.withValues(alpha: 0.4),
      onPrimaryContainer: BondhuTokens.primaryLight,
      secondary: const Color(0xFF94A3B8),
      onSecondary: Colors.black,
      surface: BondhuTokens.surfaceDark,
      onSurface: BondhuTokens.textPrimaryDark,
      surfaceContainerHighest: BondhuTokens.surfaceDarkCard,
      outline: BondhuTokens.borderDark,
      outlineVariant: BondhuTokens.borderDarkSoft,
      shadow: Colors.black45,
      scrim: Colors.black87,
      inverseSurface: BondhuTokens.surfaceLight,
      onInverseSurface: BondhuTokens.textPrimaryLight,
    );
    try {
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: BondhuTokens.bgDark,
        fontFamily: _fontFamily,
        appBarTheme: AppBarTheme(
          backgroundColor: BondhuTokens.surfaceDark,
          foregroundColor: BondhuTokens.textPrimaryDark,
          elevation: 0,
          scrolledUnderElevation: 1,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: _textStyle(
            fontWeight: FontWeight.w700,
            color: BondhuTokens.textPrimaryDark,
            fontSize: BondhuTokens.fontSizeLg,
          ),
          systemOverlayStyle: darkSystemOverlay,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: BondhuTokens.surfaceDark,
          elevation: 0,
          height: 80,
          indicatorColor: BondhuTokens.primary.withValues(alpha: 0.2),
          surfaceTintColor: Colors.transparent,
          iconTheme: WidgetStateProperty.all(IconThemeData(
            color: BondhuTokens.textPrimaryDark,
            size: 24,
          )),
          labelTextStyle: WidgetStateProperty.all(_textStyle(
            fontWeight: FontWeight.w500,
            color: BondhuTokens.textPrimaryDark,
            fontSize: 12,
          )),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: BondhuTokens.surfaceDarkCard,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: _textStyle(
            fontWeight: FontWeight.w600,
            color: BondhuTokens.textPrimaryDark,
            fontSize: BondhuTokens.fontSizeLg,
          ),
          contentTextStyle: _textStyle(
            fontWeight: FontWeight.normal,
            color: BondhuTokens.textMutedDark,
            fontSize: BondhuTokens.fontSize14,
          ),
        ),
        listTileTheme: ListTileThemeData(
          tileColor: Colors.transparent,
          textColor: BondhuTokens.textPrimaryDark,
          iconColor: BondhuTokens.textPrimaryDark,
        ),
        cardTheme: CardThemeData(
          color: BondhuTokens.surfaceDarkCard,
          elevation: 0,
          shadowColor: Colors.black45,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BondhuTokens.radiusXl),
            side: const BorderSide(color: BondhuTokens.borderDarkSoft),
          ),
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: BondhuTokens.primary,
            foregroundColor: Colors.black,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: BondhuTokens.authButtonPaddingH,
              vertical: BondhuTokens.authButtonPaddingV,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BondhuTokens.radiusFull),
            ),
            textStyle: _textStyle(
              fontSize: BondhuTokens.fontSize14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Colors.black,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: BondhuTokens.inputBgDark,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BondhuTokens.radiusMd),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BondhuTokens.radiusMd),
            borderSide: const BorderSide(color: BondhuTokens.borderDarkSoft),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BondhuTokens.radiusMd),
            borderSide: const BorderSide(color: BondhuTokens.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: BondhuTokens.authInputPaddingH,
            vertical: BondhuTokens.authInputPaddingV,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BondhuTokens.radiusMd)),
          backgroundColor: BondhuTokens.surfaceDarkCard,
          contentTextStyle: _textStyle(fontWeight: FontWeight.normal, color: BondhuTokens.textPrimaryDark, fontSize: 14),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: BondhuTokens.surfaceDarkCard,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(BondhuTokens.radius2xl)),
          ),
          showDragHandle: true,
          dragHandleColor: BondhuTokens.borderDark,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: OpenUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      );
    } catch (_) {
      return ThemeData(useMaterial3: true, brightness: Brightness.dark, colorScheme: colorScheme, scaffoldBackgroundColor: BondhuTokens.bgDark);
    }
  }
}
