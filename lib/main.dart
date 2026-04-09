import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_animations.dart';
import 'app_theme.dart';
import 'design_tokens.dart';
import 'scroll_behavior.dart';
import 'firebase_background_handler.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'services/app_language_service.dart';
import 'services/supabase_service.dart';
import 'services/block_service.dart';
import 'services/chat_vibration_service.dart';
import 'services/encrypted_local_store.dart';
import 'services/mood_status_service.dart';
import 'services/nickname_service.dart';
import 'services/push_notification_service.dart';
import 'services/secure_storage_service.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Full-screen call when app is in background or killed (FCM runs in background isolate)
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
    // Secure storage on all platforms (web: WebCrypto-backed storage; mobile: Keychain/Keystore).
    try {
      await SecureStorageService.init();
    } catch (e) {
      if (kDebugMode) debugPrint('[Bondhu] SecureStorage init failed: $e');
    }
    // Hive + encrypted store (web: IndexedDB; mobile: encrypted box). Fallback to SharedPreferences if this fails.
    try {
      await Hive.initFlutter();
      await EncryptedLocalStore.init();
    } catch (e) {
      if (kDebugMode) debugPrint('[Bondhu] EncryptedLocalStore init failed: $e');
    }
    try {
      await BlockService.instance.init();
    } catch (e) {
      if (kDebugMode) debugPrint('[Bondhu] BlockService init failed: $e');
    }
    await AppLanguageService.instance.load();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      if (kDebugMode) {
        debugPrint('FlutterError: ${details.exception}');
        debugPrintStack(stackTrace: details.stack);
      }
    };
    runApp(const BondhuApp());

    // Defer heavy work to after first frame so low-end devices paint quickly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NicknameService.instance.load();
      MoodStatusService.instance.load();
      if (!kIsWeb) {
        ChatVibrationService.instance.load();
        PushNotificationService.init();
        try {
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        } catch (e) {
          if (kDebugMode) debugPrint('[Bondhu] setPreferredOrientations: $e');
        }
      }
    });
  }, (Object error, StackTrace stack) {
    if (kDebugMode) {
      debugPrint('Uncaught error: $error');
      debugPrintStack(stackTrace: stack);
    }
  });
}

class BondhuApp extends StatefulWidget {
  const BondhuApp({super.key});

  @override
  State<BondhuApp> createState() => _BondhuAppState();
}

class _BondhuAppState extends State<BondhuApp> with WidgetsBindingObserver {
  static const String _prefDarkMode = 'bondhu_dark_mode';

  AuthUser? _currentUser;
  bool _isLoading = true;
  bool _initError = false;
  bool _isDarkMode = false; // Default light mode until prefs load

  Future<void> _initSession() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _initError = false;
    });
    try {
      // On web, first load cached user so initial paint is fast, then refresh from Supabase in background.
      if (kIsWeb) {
        final cached = await getCachedUser();
        if (!mounted) return;
        setState(() {
          _currentUser = cached;
          _isLoading = false;
          _initError = false;
        });
        // Background refresh from server; don't block UI or show loading spinner.
        getStoredUser().then((u) {
          if (!mounted) return;
          setState(() {
            _currentUser = u;
          });
        }).catchError((_) {
          // Ignore; keep cached user. If nothing cached and this fails, user will see Auth screen.
        });
        return;
      }

      final u = await getStoredUser();
      if (!mounted) return;
      setState(() {
        _currentUser = u;
        _isLoading = false;
        _initError = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _currentUser = null;
          _isLoading = false;
          _initError = true;
        });
      }
    }
  }

  void _onAuthSuccess(AuthUser user) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        setState(() {
          _currentUser = user;
          _isLoading = false;
        });
      } catch (e) {
        if (kDebugMode) debugPrint('[Bondhu] _onAuthSuccess setState: $e');
      }
    });
  }

  Future<void> _onLogout() async {
    await logout();
    if (mounted) setState(() => _currentUser = null);
  }

  void setDarkMode(bool value) {
    setState(() => _isDarkMode = value);
    _applyAndroidSystemOverlay(value);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(_prefDarkMode, value);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDarkModePref();
    _initSession();
    _applyAndroidSystemOverlay(_isDarkMode);
  }

  Future<void> _loadDarkModePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_prefDarkMode);
      if (!mounted) return;
      if (saved != null) {
        setState(() => _isDarkMode = saved);
        _applyAndroidSystemOverlay(saved);
      }
    } catch (_) {}
  }

  void _applyAndroidSystemOverlay(bool isDark) {
    if (kIsWeb) return;
    SystemChrome.setSystemUIOverlayStyle(
      isDark ? AppTheme.darkSystemOverlay : AppTheme.lightSystemOverlay,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Lightweight profile refresh on resume; do not show global loading spinner.
      getStoredUser().then((u) {
        if (!mounted) return;
        setState(() => _currentUser = u);
      }).catchError((_) {
        // Ignore; keep existing session state.
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguageService.instance,
      builder: (context, _) => MaterialApp(
        title: AppLanguageService.instance.t('app_name'),
        debugShowCheckedModeBanner: false,
        locale: AppLanguageService.instance.locale,
        theme: AppTheme.light(context),
        darkTheme: AppTheme.dark(context),
        themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) {
          return ScrollConfiguration(
            behavior: const BondhuScrollBehavior(),
            child: child!,
          );
        },
        // Shorter transition on mobile for low-end devices
        home: AnimatedSwitcher(
          duration: kIsWeb ? AppAnimations.medium : AppAnimations.fast,
          switchInCurve: AppAnimations.easeOut,
          switchOutCurve: AppAnimations.easeOut,
          transitionBuilder: (child, animation) => bondhuPageTransitionBuilder(child, animation),
          child: _buildHome(),
        ),
      ),
    );
  }

  Widget _buildHome() {
    if (_isLoading) {
      return KeyedSubtree(
        key: const ValueKey('loading'),
        child: Scaffold(
          backgroundColor: _isDarkMode ? BondhuTokens.bgDark : BondhuTokens.bgLight,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: BondhuTokens.loadingSpinnerSize,
                  height: BondhuTokens.loadingSpinnerSize,
                  child: CircularProgressIndicator(
                    strokeWidth: BondhuTokens.loadingSpinnerBorder,
                    valueColor: const AlwaysStoppedAnimation<Color>(BondhuTokens.primary),
                    backgroundColor: _isDarkMode
                        ? BondhuTokens.surfaceDarkHover
                        : BondhuTokens.borderLight,
                  ),
                ),
                const SizedBox(height: BondhuTokens.space4),
                Text(
                  AppLanguageService.instance.t('app_name').toUpperCase(),
                  style: const TextStyle(
                    fontSize: BondhuTokens.fontSize12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    color: BondhuTokens.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_initError) {
      return KeyedSubtree(
        key: const ValueKey('init_error'),
        child: Scaffold(
          backgroundColor: _isDarkMode ? BondhuTokens.bgDark : BondhuTokens.bgLight,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    AppLanguageService.instance.t('something_went_wrong'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _isDarkMode ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLanguageService.instance.t('init_error_hint'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: _isDarkMode ? BondhuTokens.textMutedDark : BondhuTokens.textMutedLight,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _initSession,
                    style: FilledButton.styleFrom(
                      backgroundColor: BondhuTokens.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    child: Text(AppLanguageService.instance.t('retry')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_currentUser == null) {
      return KeyedSubtree(
        key: const ValueKey('auth'),
        child: AuthScreen(
          onAuthSuccess: _onAuthSuccess,
        ),
      );
    }

    return KeyedSubtree(
      key: const ValueKey('home'),
      child: HomeShell(
        currentUser: _currentUser!,
        isDark: _isDarkMode,
        onDarkModeChanged: setDarkMode,
        onLogout: _onLogout,
        onProfileUpdated: (AuthUser user) {
          if (mounted) setState(() => _currentUser = user);
        },
      ),
    );
  }
}
