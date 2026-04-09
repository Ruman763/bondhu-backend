// Platform-specific FCM: mobile (Android/iOS) uses local notifications; web uses browser push.
export 'push_notification_common.dart';
export 'push_notification_service_io.dart'
  if (dart.library.html) 'push_notification_service_web.dart';
