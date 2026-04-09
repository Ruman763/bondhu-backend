import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_notification_common.dart';
import '../firebase_options.dart';
import 'chat_service.dart';

/// FCM implementation for Android/iOS. Uses local notifications for foreground.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'bondhu_chat',
    'Chat messages',
    description: 'Notifications for new chat messages',
    importance: Importance.high,
    playSound: true,
  );
  static const AndroidNotificationChannel _callChannel = AndroidNotificationChannel(
    'bondhu_incoming_call',
    'Incoming calls',
    description: 'Full-screen incoming call screen',
    importance: Importance.max,
    playSound: true,
  );
  static const int _incomingCallNotificationId = 9999;

  bool _initialized = false;
  String? _lastToken;

  String? _registeredEmail;
  void Function(String email, String token)? onTokenReady;
  void Function(Map<String, dynamic>? data)? onNotificationTapped;
  Map<String, dynamic>? _pendingLaunchData;

  static Future<void> init() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (instance._initialized) return;

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Push] Firebase init skipped (run flutterfire configure): $e');
      }
      return;
    }

    try {
      await instance._setup();
      instance._initialized = true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Push] Setup error: $e');
        debugPrintStack(stackTrace: st);
      }
    }
  }

  Future<void> _setup() async {
    await _requestPermission();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    if (Platform.isAndroid) {
      final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_channel);
      await android?.createNotificationChannel(_callChannel);
    }

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
      debugPrint('[Push] Permission: ${settings.authorizationStatus}');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    final data = message.data;
    final chatId = (data['chatId'] as String?)?.trim();
    if (chatId != null && chatId.isNotEmpty) {
      final cs = ChatService.active;
      if (cs != null && cs.isChatMutedForMessages(chatId)) {
        return;
      }
    }
    final rawCallType = data['callType'] as String?;
    final typeField = data['type'] as String?;
    final isCall = (rawCallType != null && rawCallType.isNotEmpty) || typeField == 'call';
    final callType = (rawCallType != null && rawCallType.isNotEmpty) ? rawCallType : 'audio';

    if (isCall) {
      final body = notification?.body ?? data['body'] as String? ?? 'Someone is calling you';
      final chatId = (data['chatId'] as String?) ?? '';
      final callerName = body.isNotEmpty ? body : (chatId.isNotEmpty ? chatId.split('@').first : 'Someone');
      showIncomingCallNotification(
        callerName: callerName,
        callerId: chatId,
        callType: callType,
      );
    } else if (notification != null) {
      _showLocal(
        title: notification.title ?? 'New message',
        body: notification.body ?? '',
        data: data,
      );
    } else if (data.isNotEmpty) {
      final title = data['title'] as String? ?? 'New message';
      final body = data['body'] as String? ?? data['text'] as String? ?? '';
      _showLocal(title: title, body: body, data: data);
    }
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    _handleNotificationTap(message.data);
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    final data = <String, dynamic>{};
    if (payload != null && payload.isNotEmpty) {
      try {
        for (final part in payload.split(',')) {
          final kv = part.split('=');
          if (kv.length == 2) data[kv[0].trim()] = kv[1].trim();
        }
      } catch (_) {}
    }
    if (response.actionId != null && response.actionId!.isNotEmpty) {
      data['notificationActionId'] = response.actionId;
    }
    _handleNotificationTap(data.isNotEmpty ? data : null);
  }

  void _handleNotificationTap(Map<String, dynamic>? data) {
    if (data != null && data.isNotEmpty) {
      onNotificationTapped?.call(data);
    }
  }

  /// Show full-screen incoming call notification (like WhatsApp) with Answer/Decline actions.
  Future<void> showIncomingCallNotification({
    required String callerName,
    required String callerId,
    required String callType,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final isVideo = callType == 'video';
    final title = isVideo ? 'Incoming video call' : 'Incoming call';
    final body = callerName;
    final data = <String, dynamic>{
      'type': 'call',
      'chatId': callerId,
      'callType': callType,
    };
    String? payload;
    if (data.isNotEmpty) {
      payload = data.entries.map((e) => '${e.key}=${e.value}').join(',');
    }
    if (Platform.isAndroid) {
      const androidDetails = AndroidNotificationDetails(
        'bondhu_incoming_call',
        'Incoming calls',
        channelDescription: 'Full-screen incoming call screen',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'decline',
            'Decline',
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'answer',
            'Answer',
            showsUserInterface: true,
            cancelNotification: false,
          ),
        ],
      );
      const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
      await _local.show(_incomingCallNotificationId, title, body, details, payload: payload);
    } else {
      const iosDetails = DarwinNotificationDetails(categoryIdentifier: 'INCOMING_CALL');
      const details = NotificationDetails(android: null, iOS: iosDetails);
      await _local.show(_incomingCallNotificationId, title, body, details, payload: payload);
    }
  }

  /// Cancel the incoming call notification (call when user answers or declines).
  Future<void> cancelIncomingCallNotification() async {
    await _local.cancel(_incomingCallNotificationId);
  }

  /// Call after app is ready to handle launch from notification (tap or Answer/Decline). Prefers local notification response so we get actionId.
  Future<void> deliverPendingLaunchTap() async {
    final launchDetails = await _local.getNotificationAppLaunchDetails();
    Map<String, dynamic>? data;
    if (launchDetails?.didNotificationLaunchApp == true && launchDetails?.notificationResponse != null) {
      final res = launchDetails!.notificationResponse!;
      if (res.payload != null && res.payload!.isNotEmpty) {
        data = <String, dynamic>{};
        for (final part in res.payload!.split(',')) {
          final kv = part.split('=');
          if (kv.length == 2) data[kv[0].trim()] = kv[1].trim();
        }
        if (res.actionId != null && res.actionId!.isNotEmpty) {
          data['notificationActionId'] = res.actionId;
        }
      }
    }
    if (data == null || data.isEmpty) {
      final pending = _pendingLaunchData;
      if (pending == null) return;
      _pendingLaunchData = null;
      data = pending;
    } else {
      _pendingLaunchData = null;
    }
    if (data.isNotEmpty) {
      onNotificationTapped?.call(data);
    }
  }

  Future<void> _showLocal({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    String? payload;
    if (data != null && data.isNotEmpty) {
      payload = data.entries.map((e) => '${e.key}=${e.value}').join(',');
    }
    const androidDetails = AndroidNotificationDetails(
      'bondhu_chat',
      'Chat messages',
      channelDescription: 'Notifications for new chat messages',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _local.show(
      DateTime.now().millisecondsSinceEpoch.remainder(0x7FFFFFFF),
      title,
      body,
      details,
      payload: payload,
    );
  }

  Future<void> _refreshToken() async {
    const maxAttempts = 3;
    const delayBetweenAttempts = Duration(seconds: 2);
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          _lastToken = token;
          _notifyTokenReady(token);
          if (kDebugMode) {
            debugPrint('[Push] FCM token obtained (attempt $attempt): ${token.length} chars');
            debugPrint('[Push] Token (copy for testing): $token');
          }
          return;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Push] getToken attempt $attempt error: $e');
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(delayBetweenAttempts);
      }
    }
    if (kDebugMode) {
      debugPrint('[Push] FCM token not available after $maxAttempts attempts. '
          'Check: Google Play Services, google-services.json, Firebase project, and notification permission.');
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
        message: 'Push not initialized (check Firebase config / run on device).',
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
          : 'Waiting for FCM token.',
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
