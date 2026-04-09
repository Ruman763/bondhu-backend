# Bondhu Flutter — Development Guide

## Architecture overview

- **Entry:** `main.dart` → session load → `AuthScreen` or `HomeShell`.
- **State:** No global state manager; each screen/service holds its own state. `ChatService` and `CallService` are created in `HomeShell` and passed down. `AppwriteUser` and theme (dark mode) live in `BondhuApp`.
- **Backend:** Appwrite (REST) for auth, profiles, posts, stories, storage. Socket.IO for chat and call signaling. WebRTC (flutter_webrtc) for voice/video.
- **Design:** `design_tokens.dart` (Bondhu colors, spacing, breakpoints). `app_theme.dart` (Material 3 light/dark). Plus Jakarta Sans on web; system font on mobile for performance.
- **i18n:** `lib/l10n/app_strings.dart` + `AppLanguageService` (EN/BN); speech-to-text locale follows app language.

## Key flows

1. **Auth:** Email (and optional password) → store user in Appwrite + local → `onAuthSuccess` → `HomeShell`.
2. **Chat:** `ChatView` (list + stories) → `ChatScreen` (conversation). Messages via Socket.IO; persisted in `SharedPreferences` per chat.
3. **Calls:** `CallService.initiateCall()` or incoming event → `CallOverlay` (full-screen). WebRTC offer/answer/candidates over socket.
4. **Presence (WhatsApp-style status):** For 1:1 chats the header shows "Online" / "Last seen" / "Offline". The chat server should broadcast `user_online` and `user_offline` with payload `{ email: string }` when users connect/disconnect, and optionally send `users_online` (array of emails) when a client joins so the app knows who is online. If the server does not emit these, the app falls back to "Last seen" from the peer's last message time and shows "Offline" when no info is available.
5. **Feed:** `FeedView` → load posts from Appwrite, create/like/comment; profile tab uses same view with `_viewingProfile`.
6. **Stories:** Appwrite `stories` collection (24h filter); upload to `Media` bucket → `createStory`; view in `StoryOverlay`.
7. **Contacts & friend requests:** Appwrite `friend_requests` collection (`fromUserId`, `toUserId`, `status`: pending|accepted|declined, `createdAt`). Contacts = accepted requests; private chat "Start chat" with email sends friend request if not a contact, or opens chat if already accepted.

## Development roadmap

### Done
- Auth, chat (1:1, group, global), messages, reactions, reply, voice messages, voice-to-text
- Stories (add, view, like, comment, activity)
- Voice/video calls, call overlay
- Feed (posts, create, like, comment), profile, followers/following
- Wallet UI (placeholder / coming soon)
- Chat info (search, media, pin, mute, clear, block, delete, view profile, encryption)
- Dark mode, EN/BN, push notifications (FCM), Bondhu design

### Suggested next steps
1. **Stability:** Centralized error reporting (e.g. crashlytics); retry/backoff for chat and Appwrite.
2. **Offline:** Queue failed sends; show “sent when back online” or sync state.
3. **Wallet:** Backend integration when ready; keep current UI as shell.
4. **Accessibility:** Semantics, screen reader labels, minimum tap targets.
5. **Tests:** Unit tests for `ChatService`/`AppwriteService`; widget tests for critical screens.
6. **Performance:** List virtualization where needed; image caching (e.g. cached_network_image).

## Config and env

- **Chat URL:** `lib/config/app_config.dart` — `kChatServerUrl` (debug: localhost, release: production). Override with `--dart-define=CHAT_SERVER_URL=...`.
- **Appwrite:** `lib/services/appwrite_service.dart` — endpoint, project ID, database/collection/bucket IDs. Use env or `--dart-define` if you need multiple environments.

## Shared widgets

- **`lib/widgets/empty_state.dart`:** `EmptyState(message, icon?, actionLabel?, onAction?)` and `LoadingState(message?)` for consistent empty/loading UIs. Use in lists and screens that need a centered empty or loading view.

## Adding a new screen

1. Create `lib/screens/your_screen.dart`.
2. Navigate via `Navigator.push` (or named routes if you add them in `MaterialApp`).
3. Use `BondhuTokens` and `GoogleFonts.plusJakartaSans` (or theme text styles) for consistency.
4. For empty/loading, consider `EmptyState` and `LoadingState` from `lib/widgets/empty_state.dart`.
5. For strings, add keys to `lib/l10n/app_strings.dart` (_en and _bn) and use `AppLanguageService.instance.t('key')`.

## Adding a new feature that needs backend

1. **Appwrite:** Add collection/attributes in Appwrite Console; add functions in `appwrite_service.dart` (and export models if needed).
2. **Chat/Socket:** Extend `bondhu-backend` and socket events; in `chat_service.dart` (or `call_service.dart`) listen/emit as needed.
3. **UI:** Add or extend screens; handle loading, empty, and error states.

## Common issues

- **Stories not loading:** Ensure Appwrite has `bondhu_db` → collection `stories` with attributes and read permission; bucket `Media` for uploads. Check debug console for `getStories failed: ...`.
- **Chat connects then disconnects:** Verify backend URL (and CORS on web). For Android emulator use `10.0.2.2` instead of `localhost`.
- **Voice/video no media:** Check device permissions (mic/camera) and that WebRTC is allowed by backend (TURN/STUN if needed).
