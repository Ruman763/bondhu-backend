# Bondhu Flutter App – Production Checklist

## Before release

1. **Firebase**
   - Run `flutterfire configure` and commit the updated `lib/firebase_options.dart` so iOS and web have correct `appId` values (Android is already configured).
   - Ensure `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) are in place.

2. **Assets**
   - Add `assets/sounds/incoming_call.mp3` for the call ringtone (app works without it; ringtone is skipped if missing).

3. **Signing**
   - In `android/app/build.gradle.kts`, replace `signingConfig = signingConfigs.getByName("debug")` with a release signing config (e.g. upload key for Play Store).

4. **App config**
   - Backend URL is in `lib/config/app_config.dart` (`kProductionChatServerUrl`). Change only if you use a different server.
   - Appwrite endpoint and project IDs are in `lib/services/appwrite_service.dart`.

5. **Lint & analyze**
   - Run `flutter analyze` and fix any issues.
   - Run `flutter test` if you add or change tests.

## Build commands

- **Debug:** `flutter run`
- **Release APK:** `flutter build apk --release`
- **Release App Bundle (Play Store):** `flutter build appbundle --release`
- **iOS:** `flutter build ios --release` (then archive in Xcode)

## Security notes

- No API keys or secrets are logged in release (debug prints are guarded with `kDebugMode`).
- ProGuard rules in `android/app/proguard-rules.pro` keep required SDK/plugin classes.
- E2E encryption and secure storage are used for sensitive data.
