// Background FCM handler — runs in a separate isolate when app is in background or terminated.
// Shows full-screen incoming call notification so the user sees call UI even when away from the app.

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';

const int _incomingCallNotificationId = 9999;

/// Must be top-level. Registers with FirebaseMessaging.onBackgroundMessage in main().
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final data = message.data;
  final rawCallType = data['callType'] as String?;
  final typeField = data['type'] as String?;
  final isCall = (rawCallType != null && rawCallType.isNotEmpty) || typeField == 'call';
  final callType = (rawCallType != null && rawCallType.isNotEmpty) ? rawCallType : 'audio';

  if (!isCall || !Platform.isAndroid) return;

  final title = message.notification?.title ?? data['title'] as String? ?? 'Incoming call';
  final body = message.notification?.body ?? data['body'] as String? ?? 'Someone is calling you';
  final chatId = (data['chatId'] as String?) ?? '';

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit, iOS: null);
  await plugin.initialize(initSettings);

  const callChannel = AndroidNotificationChannel(
    'bondhu_incoming_call',
    'Incoming calls',
    description: 'Full-screen incoming call screen',
    importance: Importance.max,
    playSound: true,
  );
  final androidPlugin = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(callChannel);

  final payloadData = <String, String>{
    'type': 'call',
    'chatId': chatId,
    'callType': callType,
  };
  final payload = payloadData.entries.map((e) => '${e.key}=${e.value}').join(',');

  const androidDetails = AndroidNotificationDetails(
    'bondhu_incoming_call',
    'Incoming calls',
    channelDescription: 'Full-screen incoming call screen',
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.call,
    actions: <AndroidNotificationAction>[
      AndroidNotificationAction('decline', 'Decline', cancelNotification: true),
      AndroidNotificationAction(
        'answer',
        'Answer',
        showsUserInterface: true,
        cancelNotification: false,
      ),
    ],
  );
  const details = NotificationDetails(android: androidDetails, iOS: null);
  await plugin.show(_incomingCallNotificationId, title, body, details, payload: payload);
}
