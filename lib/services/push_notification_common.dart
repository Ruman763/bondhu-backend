/// Status summary for debugging push notifications.
/// Shared by mobile (IO) and web implementations.
class PushNotificationStatus {
  const PushNotificationStatus({
    required this.initialized,
    required this.hasToken,
    this.tokenPreview,
    this.permissionGranted,
    required this.message,
  });
  final bool initialized;
  final bool hasToken;
  final String? tokenPreview;
  final bool? permissionGranted;
  final String message;
}
