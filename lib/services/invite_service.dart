/// Generate invite link and optional QR payload for "Add me" / Invite friends.
class InviteService {
  InviteService._();
  static final InviteService instance = InviteService._();

  /// Deep link base (your app's URL scheme or universal link). Update for your app.
  static const String inviteLinkBase = 'https://bondhu.app/invite';

  /// Generate invite link with optional referral id (e.g. user email hash).
  String getInviteLink({String? referralId}) {
    if (referralId != null && referralId.isNotEmpty) {
      return '$inviteLinkBase?ref=${Uri.encodeComponent(referralId)}';
    }
    return inviteLinkBase;
  }

  /// Payload string for QR code (same as link).
  String getQrPayload({String? referralId}) => getInviteLink(referralId: referralId);
}
