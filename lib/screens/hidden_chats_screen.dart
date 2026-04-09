import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';

import '../app_animations.dart';
import '../design_tokens.dart';
import '../services/app_language_service.dart';
import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/hidden_chats_service.dart';
import '../services/nickname_service.dart';
import 'chat_screen.dart';
import '../services/supabase_service.dart' show AuthUser, reauthenticateWithGoogle, verifyEmailAccountPassword;

/// PIN-protected screen that shows only hidden (private) chats. First time: set PIN; then enter PIN to unlock.
class HiddenChatsScreen extends StatefulWidget {
  const HiddenChatsScreen({
    super.key,
    required this.chatService,
    required this.callService,
    required this.currentUser,
    this.userName,
    this.userAvatarUrl,
    required this.isDark,
  });

  final ChatService chatService;
  final CallService callService;
  final AuthUser currentUser;
  final String? userName;
  final String? userAvatarUrl;
  final bool isDark;

  @override
  State<HiddenChatsScreen> createState() => _HiddenChatsScreenState();
}

class _HiddenChatsScreenState extends State<HiddenChatsScreen> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _pinSet = false;
  bool _loading = true;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _checkingBiometric = false;
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _pinError;
  bool _obscurePin = true;
  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await HiddenChatsService.instance.setAccountScope(widget.currentUser.email);
    await HiddenChatsService.instance.load();
    final hasPin = await HiddenChatsService.instance.hasPinSet();
    final biometricEnabled = await HiddenChatsService.instance.biometricEnabled();
    final biometricAvailable = await _canUseBiometric();
    if (!mounted) return;
    setState(() {
      _pinSet = hasPin;
      _loading = false;
      _biometricEnabled = biometricEnabled;
      _biometricAvailable = biometricAvailable;
      if (!hasPin) _unlocked = true; // No PIN yet: show set-PIN UI (no lock)
    });
    if (hasPin && biometricAvailable && biometricEnabled) {
      await _unlockWithBiometric();
    }
  }

  Future<void> _refreshBiometricAvailability() async {
    final available = await _canUseBiometric();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Extra safety: whenever the app goes to background, lock the Hidden Chats screen
    // so it always asks for PIN again when coming back.
    if (!_pinSet) return; // no PIN yet, nothing to lock
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_unlocked) {
        _lock();
      }
    }
  }

  Future<void> _submitSetPin() async {
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();
    if (pin.length < 4) {
      setState(() => _pinError = AppLanguageService.instance.t('pin_min_length'));
      return;
    }
    if (pin != confirm) {
      setState(() => _pinError = AppLanguageService.instance.t('pin_mismatch'));
      return;
    }
    final ok = await HiddenChatsService.instance.setPin(pin);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.mediumImpact();
      setState(() {
        _pinSet = true;
        _pinError = null;
        _pinController.clear();
        _confirmController.clear();
      });
      if (_biometricAvailable) {
        await _setBiometricEnabled(true);
        await _unlockWithBiometric();
      }
    } else {
      setState(() => _pinError = AppLanguageService.instance.t('pin_set_failed'));
    }
  }

  Future<void> _submitUnlock() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _pinError = AppLanguageService.instance.t('enter_pin'));
      return;
    }
    final ok = await HiddenChatsService.instance.verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.mediumImpact();
      setState(() {
        _unlocked = true;
        _pinError = null;
        _pinController.clear();
      });
    } else {
      setState(() => _pinError = AppLanguageService.instance.t('wrong_pin'));
    }
  }

  void _lock() {
    setState(() {
      _unlocked = false;
      _pinController.clear();
      _pinError = null;
    });
  }

  Future<bool> _canUseBiometric() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final available = await _localAuth.canCheckBiometrics;
      if (supported && available) {
        final biotypes = await _localAuth.getAvailableBiometrics();
        if (biotypes.isNotEmpty) return true;
      }
      // Some devices/OS versions report empty biometric types even when
      // system biometric auth is available. Treat support+checkability as usable.
      return supported || available;
    } catch (_) {
      return false;
    }
  }

  Future<void> _setBiometricEnabled(bool enabled) async {
    if (enabled) {
      final available = _biometricAvailable || await _canUseBiometric();
      if (!available) {
        if (!mounted) return;
        setState(() => _biometricAvailable = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric unlock is not available on this device yet. Set up fingerprint/Face ID in phone settings first.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _biometricAvailable = true);
    }
    await HiddenChatsService.instance.setBiometricEnabled(enabled);
    if (!mounted) return;
    setState(() => _biometricEnabled = enabled);
  }

  Future<void> _unlockWithBiometric() async {
    if (!_pinSet || _checkingBiometric) return;
    if (!_biometricEnabled) {
      await _setBiometricEnabled(true);
      if (!_biometricEnabled) return;
    }
    if (!_biometricAvailable) {
      await _refreshBiometricAvailability();
      if (!_biometricAvailable) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric is not ready on this device. Please set up fingerprint/Face ID in phone settings first.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    setState(() => _checkingBiometric = true);
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: AppLanguageService.instance.t('biometric_unlock_reason'),
        biometricOnly: true,
      );
      if (!mounted) return;
      if (ok) {
        HapticFeedback.mediumImpact();
        setState(() {
          _unlocked = true;
          _pinError = null;
          _pinController.clear();
        });
      }
    } catch (_) {
      // Keep PIN fallback visible.
    } finally {
      if (mounted) setState(() => _checkingBiometric = false);
    }
  }

  Future<void> _showChangePinSheet(bool isDark, Color textPrimary, Color muted) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? localError;
    bool obscure = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: isDark ? BondhuTokens.surfaceDarkCard : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppLanguageService.instance.t('change_pin'),
                    style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: currentCtrl,
                    obscureText: obscure,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: InputDecoration(
                      labelText: AppLanguageService.instance.t('current_pin'),
                      filled: true,
                      fillColor: isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF4F4F5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    style: GoogleFonts.inter(color: textPrimary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: newCtrl,
                    obscureText: obscure,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: InputDecoration(
                      labelText: AppLanguageService.instance.t('new_pin'),
                      filled: true,
                      fillColor: isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF4F4F5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    style: GoogleFonts.inter(color: textPrimary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: obscure,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: InputDecoration(
                      labelText: AppLanguageService.instance.t('confirm_new_pin'),
                      errorText: localError,
                      suffixIcon: IconButton(
                        onPressed: () => setSheetState(() => obscure = !obscure),
                        icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: muted),
                      ),
                      filled: true,
                      fillColor: isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF4F4F5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    style: GoogleFonts.inter(color: textPrimary),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () async {
                      final current = currentCtrl.text.trim();
                      final next = newCtrl.text.trim();
                      final confirm = confirmCtrl.text.trim();
                      if (next.length < 4) {
                        setSheetState(() => localError = AppLanguageService.instance.t('pin_min_length'));
                        return;
                      }
                      if (next != confirm) {
                        setSheetState(() => localError = AppLanguageService.instance.t('pin_mismatch'));
                        return;
                      }
                      final ok = await HiddenChatsService.instance.changePin(current, next);
                      if (!mounted) return;
                      if (!ok) {
                        setSheetState(() => localError = AppLanguageService.instance.t('wrong_pin'));
                        return;
                      }
                      HapticFeedback.mediumImpact();
                      if (ctx.mounted) Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(AppLanguageService.instance.t('pin_changed')),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: BondhuTokens.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(AppLanguageService.instance.t('update')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<void> _showForgotPinSheet(bool isDark, Color textPrimary, Color muted) async {
    final passCtrl = TextEditingController();
    String? localError;
    bool loading = false;
    Future<void> runReset() async {
      await HiddenChatsService.instance.resetPin(clearHiddenChats: true);
      if (!mounted) return;
      setState(() {
        _pinSet = false;
        _unlocked = true;
        _biometricEnabled = false;
        _pinError = null;
        _pinController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.instance.t('pin_reset_success')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: isDark ? BondhuTokens.surfaceDarkCard : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppLanguageService.instance.t('forgot_pin'),
                    style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLanguageService.instance.t('forgot_pin_warning'),
                    style: GoogleFonts.inter(fontSize: 13, color: muted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: AppLanguageService.instance.t('account_password'),
                      errorText: localError,
                      filled: true,
                      fillColor: isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF4F4F5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: loading
                        ? null
                        : () async {
                            final email = widget.currentUser.email?.trim().toLowerCase() ?? '';
                            final pass = passCtrl.text.trim();
                            if (email.isEmpty || pass.isEmpty) {
                              setSheetState(() => localError = AppLanguageService.instance.t('enter_password_to_continue'));
                              return;
                            }
                            setSheetState(() {
                              loading = true;
                              localError = null;
                            });
                            final ok = await verifyEmailAccountPassword(email, pass);
                            if (!mounted) return;
                            if (!ok) {
                              setSheetState(() {
                                loading = false;
                                localError = AppLanguageService.instance.t('auth_invalid_credentials');
                              });
                              return;
                            }
                            await runReset();
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: BondhuTokens.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(AppLanguageService.instance.t('reset_with_password')),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: loading
                        ? null
                        : () async {
                            setSheetState(() {
                              loading = true;
                              localError = null;
                            });
                            final ok = await reauthenticateWithGoogle();
                            if (!mounted) return;
                            if (!ok) {
                              setSheetState(() {
                                loading = false;
                                localError = AppLanguageService.instance.t('google_reauth_failed');
                              });
                              return;
                            }
                            await runReset();
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                    icon: const Icon(Icons.g_mobiledata_rounded),
                    label: Text(AppLanguageService.instance.t('reset_with_google')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    passCtrl.dispose();
  }

  void _openChat(ChatItem chat) {
    widget.chatService.selectChat(chat.id);
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
          chat: chat,
          chatService: widget.chatService,
          callService: widget.callService,
          currentUserEmail: widget.currentUser.email,
          currentUserName: widget.currentUser.name ?? widget.userName,
          userName: widget.userName,
          userAvatarUrl: widget.userAvatarUrl,
          isDark: widget.isDark,
          onNavigateToChat: (chatId) {
            Navigator.of(context).pop();
            try {
              final c = widget.chatService.chats.firstWhere((c) => c.id == chatId);
              _openChat(c);
            } catch (_) {}
          },
        ),
        transitionDuration: AppAnimations.normal,
        reverseTransitionDuration: AppAnimations.normal,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curve = CurvedAnimation(parent: animation, curve: AppAnimations.easeOut);
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(curve),
            child: FadeTransition(opacity: curve, child: child),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final surface = isDark ? BondhuTokens.surfaceDarkCard : Colors.white;
    final textPrimary = isDark ? BondhuTokens.textPrimaryDark : BondhuTokens.textPrimaryLight;
    final muted = isDark ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight;

    if (_loading) {
      return Scaffold(
        backgroundColor: isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            AppLanguageService.instance.t('hidden_chats'),
            style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
          ),
        ),
        body: const Center(child: CircularProgressIndicator(color: BondhuTokens.primary)),
      );
    }

    // PIN not set: show set-PIN form (modern card layout)
    if (!_pinSet) {
      return Scaffold(
        backgroundColor: isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            AppLanguageService.instance.t('hidden_chats'),
            style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? BondhuTokens.surfaceDarkCard : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        AppLanguageService.instance.t('set_pin_description'),
                        style: GoogleFonts.inter(fontSize: 14, color: muted, height: 1.5),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _pinController,
                        obscureText: _obscurePin,
                        keyboardType: TextInputType.number,
                        maxLength: 8,
                        decoration: InputDecoration(
                          labelText: AppLanguageService.instance.t('pin_code'),
                          errorText: _pinError,
                          filled: true,
                          fillColor: isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF4F4F5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: isDark ? BondhuTokens.borderDark : const Color(0xFFE5E7EB)),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePin ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: muted),
                            onPressed: () => setState(() => _obscurePin = !_obscurePin),
                          ),
                        ),
                        style: GoogleFonts.inter(color: textPrimary, fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _confirmController,
                        obscureText: _obscurePin,
                        keyboardType: TextInputType.number,
                        maxLength: 8,
                        decoration: InputDecoration(
                          labelText: AppLanguageService.instance.t('confirm_pin'),
                          filled: true,
                          fillColor: isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF4F4F5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: isDark ? BondhuTokens.borderDark : const Color(0xFFE5E7EB)),
                          ),
                        ),
                        style: GoogleFonts.inter(color: textPrimary, fontSize: 16),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _submitSetPin,
                        style: FilledButton.styleFrom(
                          backgroundColor: BondhuTokens.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(AppLanguageService.instance.t('set_pin'), style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  AppLanguageService.instance.t('hidden_chats_empty_hint'),
                  style: GoogleFonts.inter(fontSize: 12, color: muted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // PIN set but not unlocked: modern unlock screen
    if (!_unlocked) {
      return Scaffold(
        backgroundColor: isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            AppLanguageService.instance.t('hidden_chats'),
            style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                decoration: BoxDecoration(
                  color: isDark ? BondhuTokens.surfaceDarkCard : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: BondhuTokens.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.lock_rounded, size: 48, color: BondhuTokens.primary),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppLanguageService.instance.t('enter_pin_to_unlock'),
                      style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _pinController,
                      obscureText: _obscurePin,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      autofocus: true,
                      onSubmitted: (_) => _submitUnlock(),
                      decoration: InputDecoration(
                        labelText: AppLanguageService.instance.t('pin_code'),
                        errorText: _pinError,
                        filled: true,
                        fillColor: isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFF4F4F5),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: isDark ? BondhuTokens.borderDark : const Color(0xFFE5E7EB)),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePin ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: muted),
                          onPressed: () => setState(() => _obscurePin = !_obscurePin),
                        ),
                      ),
                      style: GoogleFonts.inter(color: textPrimary, fontSize: 17),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _submitUnlock,
                      style: FilledButton.styleFrom(
                        backgroundColor: BondhuTokens.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(AppLanguageService.instance.t('unlock'), style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => _showForgotPinSheet(isDark, textPrimary, muted),
                      child: Text(AppLanguageService.instance.t('forgot_pin')),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: (_checkingBiometric || !_biometricEnabled || !_biometricAvailable) ? null : _unlockWithBiometric,
                      icon: const Icon(Icons.fingerprint_rounded),
                      label: Text(AppLanguageService.instance.t('unlock_with_biometrics')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textPrimary,
                        side: BorderSide(color: isDark ? BondhuTokens.borderDark : const Color(0xFFE5E7EB)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      value: _biometricEnabled,
                      onChanged: (v) => _setBiometricEnabled(v),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        AppLanguageService.instance.t('use_biometrics_for_hidden_chats'),
                        style: GoogleFonts.inter(fontSize: 13, color: muted),
                      ),
                      subtitle: Text(
                        _biometricAvailable
                            ? 'Use fingerprint or Face ID for faster unlock.'
                            : 'Biometrics not detected. Set up fingerprint/Face ID, then tap refresh.',
                        style: GoogleFonts.inter(fontSize: 12, color: muted),
                      ),
                      activeThumbColor: BondhuTokens.primary,
                    ),
                    if (!_biometricAvailable)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _checkingBiometric ? null : _refreshBiometricAvailability,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Refresh biometric status'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Unlocked: show list of hidden chats
    final hiddenIds = HiddenChatsService.instance.getHiddenIds();
    final hiddenChats = widget.chatService.chats.where((c) => hiddenIds.contains(c.id)).toList();
    hiddenChats.sort((a, b) => (b.lastTime ?? '').compareTo(a.lastTime ?? ''));

    return Scaffold(
      backgroundColor: isDark ? BondhuTokens.bgDark : BondhuTokens.bgLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          AppLanguageService.instance.t('hidden_chats'),
          style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.password_rounded),
            onPressed: () => _showChangePinSheet(isDark, textPrimary, muted),
            tooltip: AppLanguageService.instance.t('change_pin'),
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline_rounded),
            onPressed: () {
              HapticFeedback.selectionClick();
              _lock();
            },
            tooltip: AppLanguageService.instance.t('lock'),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: HiddenChatsService.instance.hiddenIds,
        builder: (context, ids, _) {
          final list = widget.chatService.chats.where((c) => ids.contains(c.id)).toList();
          list.sort((a, b) => (b.lastTime ?? '').compareTo(a.lastTime ?? ''));
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: BondhuTokens.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.inbox_rounded, size: 48, color: BondhuTokens.primary.withValues(alpha: 0.7)),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AppLanguageService.instance.t('no_hidden_chats'),
                      style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w600, color: textPrimary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      AppLanguageService.instance.t('hidden_chats_empty_hint'),
                      style: GoogleFonts.inter(fontSize: 14, color: muted, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            itemCount: list.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final chat = list[i];
              return _buildChatTile(context, chat, isDark, textPrimary, muted, surface);
            },
          );
        },
      ),
    );
  }

  Widget _buildChatTile(BuildContext context, ChatItem chat, bool isDark, Color textPrimary, Color muted, Color surface) {
    const tileRadius = 18.0;
    const avatarSize = 48.0;
    final cardBg = isDark ? BondhuTokens.surfaceDarkCard : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openChat(chat),
        onLongPress: () => _showRemoveFromHidden(context, chat, isDark),
        borderRadius: BorderRadius.circular(tileRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(tileRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.05),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: avatarSize / 2,
                backgroundColor: isDark ? BondhuTokens.surfaceDarkHover : const Color(0xFFE5E7EB),
                backgroundImage: chat.avatar != null && chat.avatar!.isNotEmpty ? NetworkImage(chat.avatar!) : null,
                child: chat.avatar == null ? Icon(Icons.person, color: BondhuTokens.textMutedDark, size: 20) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      NicknameService.instance.getDisplayName(chat),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      chat.lastMessage?.isNotEmpty == true ? chat.lastMessage! : AppLanguageService.instance.t('encrypted_message'),
                      style: GoogleFonts.inter(fontSize: 12, color: muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                chat.lastTime ?? '',
                style: GoogleFonts.inter(fontSize: 10, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRemoveFromHidden(BuildContext context, ChatItem chat, bool isDark) {
    final t = AppLanguageService.instance.t;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? BondhuTokens.surfaceDarkCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_rounded, color: BondhuTokens.primary),
                title: Text(t('remove_from_hidden'), style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await HiddenChatsService.instance.removeHidden(chat.id);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

