import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_fonts/google_fonts.dart';

import '../app_animations.dart';
import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/supabase_service.dart'
    show AuthUser, sendPasswordResetEmail, signInWithEmail, signInWithGoogle, signUpWithEmail, storeUser;
import '../widgets/bondhu_app_logo.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.onAuthSuccess,
  });

  final ValueChanged<AuthUser> onAuthSuccess;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _busy = false;
  bool _isRegister = false;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  static AuthUser get _guestUser => AuthUser(
        email: 'demo@bondhu.app',
        name: 'Demo User',
        avatar: 'https://api.dicebear.com/7.x/avataaars/svg?seed=demo',
        docId: null,
        bio: null,
        location: null,
        followers: [],
        following: [],
      );

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  static bool _isValidEmail(String s) {
    if (s.isEmpty) return false;
    return RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$').hasMatch(s);
  }

  Future<void> _enterAsGuest() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      await storeUser(_guestUser);
      if (!mounted) return;
      widget.onAuthSuccess(_guestUser);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authErrorMessage(Object e) {
    final l10n = AppLanguageService.instance;
    final fallback = l10n.t('something_went_wrong');
    final s = e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '');
    final m = s.toLowerCase();
    if (m.contains('rate limit')) {
      return 'Too many login attempts right now. Please wait 1 minute and try again.';
    }
    if (m.contains('invalid credentials') || m.contains('wrong password')) {
      return l10n.t('auth_invalid_credentials');
    }
    if (m.contains('already exists')) {
      return l10n.t('auth_email_exists');
    }
    if (s.toLowerCase().contains('verification email sent')) {
      return s;
    }
    if (s.toLowerCase().contains('sign_in_failed') && s.contains('12500')) {
      return 'Google sign-in setup incomplete (Error 12500). Add your Android SHA-1/SHA-256 in Firebase, then download new google-services.json and rebuild the app.';
    }
    if (s.toLowerCase().contains('google token not available')) {
      return 'Google sign-in setup issue. Check GOOGLE_WEB_CLIENT_ID and Google provider setup.';
    }
    if (s.toLowerCase().contains('google sign-in failed')) {
      return 'Google sign-in failed. Check your Google sign-in configuration.';
    }
    return s.isEmpty ? fallback : '$fallback $s';
  }

  Future<void> _handleForgotPassword() async {
    if (_busy) return;
    final email = _emailController.text.trim().toLowerCase();
    if (!_isValidEmail(email)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('enter_valid_email')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await sendPasswordResetEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('password_reset_hint')),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_authErrorMessage(e)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleEmailAuth() async {
    if (_busy) return;
    if (_formKey.currentState?.validate() != true) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;
      final name = _nameController.text.trim();
      final user = _isRegister
          ? await signUpWithEmail(email, password, name)
          : await signInWithEmail(email, password);
      if (!mounted) return;
      widget.onAuthSuccess(user);
    } catch (e) {
      debugPrint('[AuthScreen] Email auth error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_authErrorMessage(e)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleGoogleAuth() async {
    if (_busy) return;
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('google_login_web_hint')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      final user = await signInWithGoogle();
      if (!mounted) return;
      widget.onAuthSuccess(user);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_authErrorMessage(e)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static TextStyle _titleStyle(BuildContext context, {required double fontSize, required FontWeight w, required Color color}) {
    if (kIsWeb) {
      return GoogleFonts.plusJakartaSans(fontSize: fontSize, fontWeight: w, color: color);
    }
    return TextStyle(fontSize: fontSize, fontWeight: w, color: color);
  }

  Widget _guestButton(BuildContext context) {
    final lang = AppLanguageService.instance;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _busy ? null : _enterAsGuest,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.symmetric(vertical: BondhuTokens.authButtonPaddingV),
          backgroundColor: BondhuTokens.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: BondhuTokens.primary.withValues(alpha: 0.4),
        ),
        child: _busy
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                lang.t('continue_demo'),
                style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
      ),
    );
  }

  Widget _googleButton(BuildContext context, bool isDark) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _handleGoogleAuth,
        icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
        label: Text(AppLanguageService.instance.t('continue_google')),
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
          side: BorderSide(color: isDark ? BondhuTokens.borderDarkSoft : BondhuTokens.borderLight),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _bodyContent(BuildContext context, bool isDark) {
    final lang = AppLanguageService.instance;
    final formPadH = BondhuTokens.responsive(context, 28.0, 48.0);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: formPadH, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FadeSlideIn(
            duration: AppAnimations.medium,
            child: Column(
              children: [
                const BondhuAppLogo(size: BondhuTokens.authLogoSize),
                SizedBox(height: BondhuTokens.authLogoMarginBottom),
                Text(
                  'Bondhu',
                  style: _titleStyle(
                    context,
                    fontSize: BondhuTokens.fontSize2xl,
                    w: FontWeight.w800,
                    color: isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          FadeSlideIn(
            delay: AppAnimations.fast,
            child: Text(
              lang.t('welcome_back'),
              textAlign: TextAlign.center,
              style: _titleStyle(
                context,
                fontSize: BondhuTokens.responsive(context, 22.0, BondhuTokens.fontSize3xl),
                w: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF18181B),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FadeSlideIn(
            delay: const Duration(milliseconds: 140),
            child: Text(
              lang.t('auth_rebuilding_subtitle'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
              ),
            ),
          ),
          const SizedBox(height: 32),
          FadeSlideIn(
            delay: const Duration(milliseconds: 180),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E7EB),
                ),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                  if (_isRegister) ...[
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: AppLanguageService.instance.t('full_name'),
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                      ),
                      validator: (_) => null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: AppLanguageService.instance.t('email'),
                      prefixIcon: const Icon(Icons.email_outlined, size: 20),
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return AppLanguageService.instance.t('enter_your_email');
                      if (!_isValidEmail(value)) return AppLanguageService.instance.t('enter_valid_email');
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: AppLanguageService.instance.t('password'),
                      prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    ),
                    validator: (v) {
                      final value = v ?? '';
                      if (value.isEmpty) return AppLanguageService.instance.t('password_required');
                      if (_isRegister && value.length < 8) return AppLanguageService.instance.t('password_min_length');
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _handleEmailAuth,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: BondhuTokens.authButtonPaddingV),
                        backgroundColor: BondhuTokens.primary,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: BondhuTokens.primary.withValues(alpha: 0.4),
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(_isRegister ? AppLanguageService.instance.t('sign_up') : AppLanguageService.instance.t('sign_in')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _isRegister = !_isRegister;
                            }),
                    child: Text(
                      _isRegister
                          ? AppLanguageService.instance.t('already_have_account')
                          : AppLanguageService.instance.t('dont_have_account'),
                    ),
                  ),
                  if (!_isRegister)
                    TextButton(
                      onPressed: _busy ? null : _handleForgotPassword,
                      child: Text(AppLanguageService.instance.t('forgot_password')),
                    ),
                ],
              ),
            ),
          ),
          ),
          const SizedBox(height: 10),
          FadeSlideIn(
            delay: const Duration(milliseconds: 200),
            child: _googleButton(context, isDark),
          ),
          const SizedBox(height: 10),
          FadeSlideIn(
            delay: const Duration(milliseconds: 220),
            child: _guestButton(context),
          ),
          const SizedBox(height: 10),
          FadeSlideIn(
            delay: const Duration(milliseconds: 240),
            child: Text(
              'Secure login powered by Bondhu',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 768;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!isWide) {
      return Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: isDark
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF020617), Color(0xFF0F172A), Color(0xFF020617)],
                    stops: [0.0, 0.6, 1.0],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFCCFBF1), Color(0xFFD1FAE5), Color(0xFFECFDF5), Color(0xFFFFFFFF)],
                    stops: [0.0, 0.33, 0.7, 1.0],
                  ),
          ),
          child: SafeArea(
            child: Center(child: _bodyContent(context, isDark)),
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: BondhuTokens.authContainerMaxWidth,
            minHeight: BondhuTokens.authContainerMinHeight,
          ),
          width: BondhuTokens.authContainerMaxWidth,
          decoration: BoxDecoration(
            color: isDark ? BondhuTokens.authContainerDark : BondhuTokens.surfaceLight,
            borderRadius: BorderRadius.circular(BondhuTokens.authContainerRadius),
            boxShadow: BondhuTokens.authContainerShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        BondhuTokens.primaryDark,
                        BondhuTokens.primary,
                        Color(0xFF14B8A6),
                        BondhuTokens.primaryLight,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: BondhuTokens.authOverlayPaddingH),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            AppLanguageService.instance.t('welcome_back'),
                            textAlign: TextAlign.center,
                            style: _titleStyle(
                              context,
                              fontSize: BondhuTokens.fontSize3xl + 6,
                              w: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: BondhuTokens.space4),
                          Text(
                            AppLanguageService.instance.t('auth_rebuilding_subtitle'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: BondhuTokens.fontSize14,
                              height: 1.5,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  color: isDark ? BondhuTokens.authContainerDark : BondhuTokens.surfaceLight,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: BondhuTokens.responsive(context, 28.0, 48.0), vertical: 24),
                      child: FadeSlideIn(
                        delay: const Duration(milliseconds: 140),
                        child: _bodyContent(context, isDark),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
