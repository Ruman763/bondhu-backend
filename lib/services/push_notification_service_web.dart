import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_notification_common.dart';
import '../firebase_options.dart';

/// FCM implementation for web. Requires a real web app in Firebase and
/// [DefaultFirebaseOptions.webVapidKey] set (from Cloud Messaging > Web Push certificates).
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  bool _initialized = false;
  String? _lastToken;

  String? _registeredEmail;
  void Function(String email, String token)? onTokenReady;
  void Function(Map<String, dynamic>? data)? onNotificationTapped;
  Map<String, dynamic>? _pendingLaunchData;

  static Future<void> init() async {
    if (instance._initialized) return;

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Push] Web Firebase init failed (add web app in Firebase Console / run flutterfire configure): $e');
      }
      return;
    }

    try {
      await instance._setup();
      instance._initialized = true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Push] Web setup error: $e');
        debugPrintStack(stackTrace: st);
      }
    }
  }

  Future<void> _setup() async {
    await _requestPermission();

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null && initialMessage.data.isNotEmpty) {
      _pendingLaunchData = Map<String, dynamic>.from(initialMessage.data);
    }

    await _refreshToken();
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _lastToken = token;
      _notifyTokenReady(token);
    });
  }

  Future<void> _requestPermission() async {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (kDebugMode) {
      debugPrint('[Push] Web permission: ${settings.authorizationStatus}');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      final n = message.notification;
      debugPrint('[Push] Web foreground: ${n?.title ?? message.data['title'] ?? 'New message'}');
    }
    // On web we don't show a local notification when app is in foreground;
    // the message is still delivered and the UI can react if needed.
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    _handleNotificationTap(message.data);
  }

  void _handleNotificationTap(Map<String, dynamic>? data) {
    if (data != null && data.isNotEmpty) {
      onNotificationTapped?.call(data);
    }
  }

  void deliverPendingLaunchTap() {
    final pending = _pendingLaunchData;
    if (pending == null) return;
    _pendingLaunchData = null;
    onNotificationTapped?.call(pending);
  }

  /// No-op on web (full-screen incoming call notifications are mobile-only).
  Future<void> showIncomingCallNotification({
    required String callerName,
    required String callerId,
    required String callType,
  }) async {}

  /// No-op on web.
  Future<void> cancelIncomingCallNotification() async {}

  Future<void> _refreshToken() async {
    const vapidKey = DefaultFirebaseOptions.webVapidKey;
    if (vapidKey.isEmpty) {
      if (kDebugMode) {
        debugPrint('[Push] Web: set DefaultFirebaseOptions.webVapidKey (Firebase Console > Cloud Messaging > Web Push certificates) to get FCM token.');
      }
      return;
    }

    const maxAttempts = 3;
    const delayBetweenAttempts = Duration(seconds: 2);
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final token = await FirebaseMessaging.instance.getToken(vapidKey: vapidKey);
        if (token != null && token.isNotEmpty) {
          _lastToken = token;
          _notifyTokenReady(token);
          if (kDebugMode) {
            debugPrint('[Push] Web FCM token obtained (attempt $attempt): ${token.length} chars');
          }
          return;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Push] Web getToken attempt $attempt error: $e');
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(delayBetweenAttempts);
      }
    }
    if (kDebugMode) {
      debugPrint('[Push] Web FCM token not available. Check web appId and webVapidKey in firebase_options.dart.');
    }
  }

  Future<void> refreshToken() async {
    if (!_initialized) return;
    await _refreshToken();
  }

  Future<PushNotificationStatus> getStatus() async {
    if (!_initialized) {
      return PushNotificationStatus(
        initialized: false,
        hasToken: false,
        tokenPreview: null,
        permissionGranted: null,
        message: 'Push not initialized (add web app + VAPID key in Firebase, then set firebase_options.dart).',
      );
    }
    bool? permissionGranted;
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      permissionGranted = settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (_) {}
    final preview = _lastToken != null && _lastToken!.length > 20
        ? '${_lastToken!.substring(0, 12)}...${_lastToken!.substring(_lastToken!.length - 8)}'
        : _lastToken;
    return PushNotificationStatus(
      initialized: true,
      hasToken: _lastToken != null,
      tokenPreview: preview,
      permissionGranted: permissionGranted,
      message: _lastToken != null
          ? (permissionGranted == true ? 'Ready. Send a test from Firebase Console.' : 'Token ready; check notification permission.')
          : 'Waiting for FCM token (ensure webVapidKey is set).',
    );
  }

  void _notifyTokenReady(String token) {
    final email = _registeredEmail ?? '';
    onTokenReady?.call(email, token);
  }

  void registerTokenWithBackend(String email, void Function(String token) sendToServer) {
    _registeredEmail = email;
    if (_lastToken != null) sendToServer(_lastToken!);
    onTokenReady = (e, token) {
      if (e == email) sendToServer(token);
    };
  }

  String? get lastToken => _lastToken;
  bool get isInitialized => _initialized;
}
