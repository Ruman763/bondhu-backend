# Bondhu — Flutter App

**Bondhu** is a social and messaging app built with Flutter for **iOS**, **Android**, and **Web**. It offers chat, feed, stories, voice/video calls, and wallet (UI) with a modern Bondhu design system.

---

## Features

| Area | Features |
|------|----------|
| **Chat** | 1:1 and group chats, global room, real-time messages, reactions, reply, voice messages, voice-to-text, image/file send, end-to-end encryption (UI), search in conversation, view media, pin/mute/clear/block, chat info |
| **Stories** | 24h stories, add from gallery, view/like/comment, activity, delete (owner) |
| **Calls** | Voice and video calls (WebRTC), incoming/outgoing UI, live captions |
| **Feed** | Home feed, create post (text + image/video), like/comment, profile grid, followers/following, reels placeholder, language (EN/BN) |
| **Wallet** | Wallet UI (recharge, send, scan, services) — coming soon |
| **App** | Auth (email), dark mode, Bangla/English, push notifications, Bondhu design tokens |

---

## Run the app

From the project root (`bondhu_flutter/`):

```bash
# Web
flutter run -d chrome
# or build: flutter build web

# Android (device/emulator required)
flutter run -d android

# iOS (Mac + Xcode + simulator/device)
flutter run -d ios
```

List devices: `flutter devices`

---

## Setup

### 1. Flutter

- Install [Flutter](https://docs.flutter.dev/get-started/install) (SDK ^3.11.0).
- Run `flutter pub get` in the project root.

### 2. Backend / services

- **Appwrite:** Used for auth, profiles, posts, stories, storage. Configure endpoint and project in `lib/services/appwrite_service.dart` (or env). Ensure database `bondhu_db` and collections (`profiles`, `posts`, `stories`) and bucket `Media` exist with correct permissions.
- **Chat server:** Socket.IO server for real-time chat and signaling for calls.
  - **Debug:** Uses local server at `http://localhost:3000` (Android emulator: `http://10.0.2.2:3000`). Start with:
    ```bash
    cd bondhu-backend && npm install && npm start
    ```
  - **Release:** Uses production URL. See `lib/config/app_config.dart` and `bondhu-backend/README.md` for overrides (e.g. `--dart-define=CHAT_SERVER_URL=...`).
- **Firebase (optional):** For FCM push notifications. Add `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) and ensure `firebase_core` / `firebase_messaging` are configured.

### 3. Environment

- Chat server URL can be overridden via `--dart-define=CHAT_SERVER_URL=<url>` when building or running.

---

## Project layout

```
lib/
├── main.dart                 # App entry, auth gate, theme
├── app_theme.dart            # Light/dark theme, Material 3
├── app_animations.dart       # Page transitions, FadeSlideIn
├── design_tokens.dart        # Bondhu colors, spacing, breakpoints
├── widgets/
│   └── empty_state.dart     # EmptyState, LoadingState (reusable)
├── config/
│   ├── app_config.dart       # Chat server URL (debug/release)
│   └── app_config_io.dart    # Platform-specific config
├── l10n/
│   └── app_strings.dart      # EN/BN strings (AppLanguageService)
├── services/
│   ├── appwrite_service.dart # Appwrite: auth, profiles, posts, stories, storage
│   ├── chat_service.dart     # Socket.IO chat, messages, typing, reactions
│   ├── call_service.dart     # WebRTC signaling, voice/video calls
│   ├── app_language_service.dart
│   ├── notification_service.dart
│   └── push_notification_service.dart
├── screens/
│   ├── auth_screen.dart
│   ├── home_shell.dart       # Bottom nav: Chat, Feed, Wallet
│   ├── chat_view.dart        # Chat list + stories
│   ├── chat_screen.dart      # Single conversation
│   ├── chat_info_screen.dart # Chat info (search, media, mute, etc.)
│   ├── story_overlay.dart
│   ├── call_overlay.dart
│   ├── feed_view.dart        # Feed, profile, posts
│   ├── followers_following_screen.dart
│   ├── wallet_view.dart
│   └── notification_panel.dart
└── utils/
    ├── voice_util_io.dart
    └── voice_util_stub.dart
```

---

## Docs

- [Flutter](https://docs.flutter.dev/)
- [Dart](https://dart.dev/)
- See **DEVELOPMENT.md** in this repo for architecture notes and roadmap.
