# Copilot Instructions for Bondhu Flutter

## What this repo is
- Flutter social/messaging app with Appwrite backend, Socket.IO chat, WebRTC calls, and optional Firebase FCM.
- Entry point: `lib/main.dart` → auth session load → `AuthScreen` or `HomeShell`.
- Primary backend glue lives in `lib/services/appwrite_service.dart` and `lib/services/chat_service.dart`.

## Architecture and important boundaries
- No global state manager. Most state is local to screens/services.
- `BondhuApp` owns `AppwriteUser` session and theme; `HomeShell` creates/passes down chat/call services.
- Appwrite is used for auth, profiles, posts, stories, storage, and queued messages.
- Socket.IO is used for realtime chat, presence, and call signaling; WebRTC is used for voice/video media.
- `lib/config/app_config.dart` controls chat backend URL and optional TURN config via `--dart-define`.

## Patterns to follow
- Use `AppLanguageService.instance.t('key')` for user-facing text and `lib/l10n/app_strings.dart` for EN/BN strings.
- Reuse `lib/widgets/empty_state.dart` for empty/loading scenarios.
- Keep backend schema aligned with `lib/services/appwrite_service.dart` IDs and `docs/APPWRITE_SELF_HOSTED_SCHEMA.md`.
- Platform-specific push notifications are exported from `lib/services/push_notification_service.dart`.
- `AuthScreen` and `HomeShell` are the main auth/navigation boundaries.

## Common workflows
- Install deps: `flutter pub get`
- Run web: `flutter run -d chrome`
- Run Android: `flutter run -d android`
- Run iOS: `flutter run -d ios`
- Use local chat backend: `flutter run --dart-define=CHAT_SERVER_URL=http://localhost:3000`
- Android emulator local backend: use `http://10.0.2.2:3000` if needed.
- Tests: `flutter test`

## Integration notes
- Appwrite constants are hard-coded in `lib/services/appwrite_service.dart`; update that file for new collections or project settings.
- Chat server URL defaults to production in `lib/config/app_config.dart`.
- Firebase setup is optional; `lib/firebase_options.dart` and `firebase_background_handler.dart` show how FCM is initialized.
- `docs/APPWRITE_FOLLOW_PERMISSIONS.md` documents Appwrite permission patterns relevant to follow/unfollow logic.

## When editing
- Preserve `ChatService`/`CallService` separation: realtime socket signaling belongs in service classes, UI belongs in `lib/screens/`.
- New backend features often require matching changes in `appwrite_service.dart`, socket event handlers in `chat_service.dart`, and screen/UI updates in `lib/screens/`.
- Follow naming and theme conventions: `BondhuTokens`, `AppTheme`, `GoogleFonts.plusJakartaSans`, and `design_tokens.dart`.
