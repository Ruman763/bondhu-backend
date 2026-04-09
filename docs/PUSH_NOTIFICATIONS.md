# Push Notifications — How to Check & Why They Might Not Work

This app uses **Firebase Cloud Messaging (FCM)** with **flutter_local_notifications** for chat push notifications.

---

## How to check if push is working

### 1. In the app (Settings)

1. Run the app on a **real Android or iOS device** (not web, not simulator).
2. Log in and open **Settings** (profile/settings in the app).
3. Find the **PUSH NOTIFICATIONS** section. It shows:
   - **Ready. Send a test from Firebase Console.** — FCM is set up, you have a token, and permission is granted. You can send a test message (see step 2).
   - **Token ready; check notification permission.** — Token exists but permission may be denied. Open device Settings → Apps → Bondhu → Notifications and allow.
   - **Push not initialized…** — Firebase config is missing or wrong. Run `flutterfire configure` and add `google-services.json` / `GoogleService-Info.plist`.
   - **Waiting for FCM token.** — Firebase is initializing or failed to get a token; check debug logs.

### 2. Debug console (token for testing)

When you run in **debug mode** (`flutter run`), the app prints the FCM token in the console after init:

- Look for: `[Push] FCM token obtained...` and `[Push] Token (copy for Firebase Console): <long string>`.
- Copy that token to send a test message from Firebase (see below).

### 3. Send a test message (Firebase Console)

1. Open [Firebase Console](https://console.firebase.google.com/) → your project (**bondhu-a6497**).
2. Go to **Engage** → **Messaging** (or **Cloud Messaging**).
3. Click **Create your first campaign** or **New campaign** → **Firebase Notification messages**.
4. Enter title and body (e.g. "Test", "Push test from Bondhu").
5. Click **Send test message**.
6. Paste the **FCM token** you copied from the app (from debug console or from your backend if you store it).
7. Send. You should see the notification on the device within a few seconds.

If the test message arrives, push is working on the device. If your **chat** doesn’t trigger pushes, the issue is usually that your backend isn’t sending FCM when a new message arrives (see “Token never sent to your server” below).

---

## Why they might not work

## 1. **Firebase not configured**
- You must run **`flutterfire configure`** and have valid:
  - **Android:** `android/app/google-services.json`
  - **iOS:** `ios/Runner/GoogleService-Info.plist`
  - **Web:** Add a Web app in Firebase Console, then run `flutterfire configure` (or paste the web config into `lib/firebase_options.dart`). In Firebase Console → **Project Settings** → **Cloud Messaging** → **Web Push certificates**, generate a key pair and set `DefaultFirebaseOptions.webVapidKey` in `lib/firebase_options.dart` to that key (required for FCM on web).
- Without these, Firebase init fails and the service returns early. No token is requested.
- **Web:** Push is supported; the app uses a web-specific implementation that requests permission and gets a token via `getToken(vapidKey: webVapidKey)`. Non-mobile platforms other than web (e.g. desktop) do not run the push service.

## 2. **No FCM token sent to your backend**
- The app gets an FCM token only after Firebase and FCM are initialized.
- The token is delivered via `PushNotificationService.onTokenReady` or `registerTokenWithBackend(email, sendToServer)`.
- If your **chat/server backend** never receives and stores this token per user, it cannot send targeted push messages. Ensure your backend:
  - Saves the FCM token for the logged-in user (e.g. by email/userId).
  - Uses that token when sending FCM messages (e.g. when a new message arrives for that user).

## 3. **Permissions**
- **Android 13+:** `POST_NOTIFICATIONS` is in the manifest; the app still must **request** permission at runtime (FCM’s `requestPermission()` is used in `_requestPermission()`). If the user denies, no notifications are shown.
- **iOS:** Notification permission is requested in `DarwinInitializationSettings`. If the user denies or doesn’t accept the prompt, no alerts.

## 4. **Running in the wrong environment**
- **Web:** Push is supported. Ensure you have a Firebase Web app and `webVapidKey` set in `firebase_options.dart` (see §1). Test in a browser that supports Push (e.g. Chrome).
- **iOS Simulator:** Push is unreliable; use a **physical device** for testing.
- **Debug vs release:** Ensure you’re testing with the same build type (e.g. release) and same Firebase project as your server.

## 5. **Backend not sending FCM messages**
- Even with a valid token and permissions, pushes only appear if **your server** sends an FCM payload to that token (e.g. when someone sends a message). Verify:
  - Server has the correct FCM server key / service account.
  - Server sends to the token that the app registered for that user.
  - Payload includes at least `notification` or `data` so the app or OS can show it.

## 6. **Battery / OS restrictions**
- On some Android devices, background and notification delivery are restricted for apps that are battery-optimized or not “allowed” to run in the background. The user may need to disable battery optimization for the app or allow background activity.

## Quick checklist

- [ ] **Check in app:** Settings → PUSH NOTIFICATIONS shows “Ready” and a token preview.
- [ ] **Check console:** Debug run shows `[Push] FCM token obtained` and the full token.
- [ ] **Test message:** Firebase Console → Messaging → Send test message with that token; notification appears on device.
- [ ] `flutterfire configure` run; `google-services.json` and `GoogleService-Info.plist` present.
- [ ] Testing on a real Android/iOS device (not web, not only simulator).
- [ ] Notification permission granted when prompted.
- [ ] Backend receives and stores FCM token for the current user.
- [ ] Backend sends FCM messages to that token when appropriate (e.g. new message).
