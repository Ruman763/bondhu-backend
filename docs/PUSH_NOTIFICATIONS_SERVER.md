# Why Push Notifications Aren’t Working & What to Do on the Server

## How the app works (client side)

1. **FCM token**  
   On Android/iOS the app gets a Firebase Cloud Messaging (FCM) token and sends it to your **chat server** over the existing Socket.IO connection.

2. **Sending the token to the server**  
   When the user is logged in and the socket is connected, the app emits:

   ```text
   socket.emit('register_fcm', { email: string, token: string })
   ```

   - `email`: current user’s email (lowercase).
   - `token`: FCM device token for push.

3. **When the user taps a notification**  
   The app expects the FCM **data** payload to include:

   - `chatId` (required) – so it can open the correct chat (e.g. `group_global` or the other user’s email for private chat).

   Optional for notification title/body:

   - `title` – e.g. sender name or “New message”.
   - `body` – e.g. message preview.

So: **push will not work until the server stores these tokens and sends FCM messages when someone receives a new message.**

---

## What the server must do

Your chat server (e.g. `bondhu-chat-server` on Render) must do three things:

### 1. Listen for `register_fcm` and store tokens

- On Socket.IO event **`register_fcm`** with payload `{ email, token }`:
  - Store a mapping: **user identifier (e.g. email) → FCM token(s)**.
  - One user can have multiple devices; store multiple tokens per user (e.g. array or set) and optionally limit how many per user.
- When the same user connects again with a new token, update or add that token for that user.
- Optionally: when the socket disconnects, you can keep the token (so push still works when the app is closed) or remove it if you only want push for offline users.

Example (conceptual):

```js
// Example: in-memory store (use Redis/DB in production)
const fcmTokensByEmail = new Map(); // email -> Set of tokens

io.on('connection', (socket) => {
  socket.on('register_fcm', ({ email, token }) => {
    if (!email || !token) return;
    const normalized = email.trim().toLowerCase();
    if (!fcmTokensByEmail.has(normalized)) {
      fcmTokensByEmail.set(normalized, new Set());
    }
    fcmTokensByEmail.get(normalized).add(token);
  });
});
```

### 2. When a message is delivered to a recipient, send FCM if needed

Whenever the server delivers a message to a user (e.g. private message or group message):

- Decide the **recipient user** (e.g. for private chat: the user who is not the sender; for global/group: all members except sender).
- For each recipient:
  - Check if that recipient has any stored FCM tokens.
  - Optionally: only send push if the recipient is “offline” or not currently viewing that chat (if your server tracks presence/current chat).
- For each token of that recipient, call **Firebase Admin SDK** (or FCM HTTP v1 API) to send a push.

Payload the app expects in **data**:

- `chatId` – **required**. Use:
  - For global chat: `group_global`
  - For private chat: the **other** user’s id (e.g. sender’s email for the recipient)
  - For group chat: your group id (e.g. `group_xxx`)
- `title` (optional) – e.g. chat name or sender name.
- `body` (optional) – e.g. message preview (first 100 chars of text).

Example (Node.js with Firebase Admin SDK):

```js
const admin = require('firebase-admin');

// Initialize once at server start (use service account key from Firebase Console)
admin.initializeApp({ credential: admin.credential.applicationDefault() });
// Or: admin.credential.cert(require('./path-to-serviceAccountKey.json'))

function getTokensForUser(email) {
  const normalized = (email || '').trim().toLowerCase();
  return Array.from(fcmTokensByEmail.get(normalized) || []);
}

async function sendPushToRecipient(recipientEmail, { chatId, title, body }) {
  const tokens = getTokensForUser(recipientEmail);
  if (tokens.length === 0) return;

  const message = {
    data: {
      chatId: String(chatId || ''),
      title: title || 'New message',
      body: body || '',
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'bondhu_chat',
        title: title || 'New message',
        body: body || '',
      },
    },
    apns: {
      payload: { aps: { sound: 'default', badge: 1 } },
      fcmOptions: {},
    },
    tokens,
  };

  const res = await admin.messaging().sendEachForMulticast(message);
  // Optional: remove invalid tokens (res.responses[i].success === false)
}
```

Call this when you would normally “deliver” a message to a user (e.g. when emitting `private_message` to the recipient’s socket, or when storing a message for a group). For example:

- On **private_message**: recipient = `message.targetId` (or the other user); `chatId` = same as targetId; title = sender name; body = message text.
- On **global/group message**: recipient = each member (or each subscribed user); `chatId` = `group_global` or group id; title/body as above.

### 3. Use a valid Firebase project and server credentials

- The app already uses Firebase project **bondhu-a6497** (see `lib/firebase_options.dart`).
- On the **server** you must use the **same project** and **Firebase Admin** (service account), not the client config.
- In Firebase Console:
  1. Project Settings → Service accounts.
  2. Generate a new private key (JSON).
  3. On the server, use this JSON with `admin.credential.cert(...)` or set `GOOGLE_APPLICATION_CREDENTIALS` and use `admin.credential.applicationDefault()`.

Without this, the server cannot call FCM and push will not be sent.

---

## Checklist

| Step | Done? |
|------|--------|
| Server listens for `register_fcm` and stores `email → token(s)` | |
| When a message is delivered to a user, server gets that user’s FCM tokens | |
| Server calls FCM (Firebase Admin) to send a message with `data.chatId` (+ optional title/body) | |
| Firebase Admin is initialized with service account for project bondhu-a6497 | |
| Invalid/expired tokens are removed after send failures | |

---

## Summary

- **Why push doesn’t work:** The app sends the FCM token to your chat server and is ready to receive FCM and open chats by `chatId`. The missing part is the **server**: it must store tokens and send FCM messages when delivering messages.
- **What to do on the server:**  
  1) Handle `register_fcm` and store tokens per user.  
  2) When delivering a message, send an FCM message to the recipient’s token(s) with `data.chatId` (and optional title/body).  
  3) Use Firebase Admin SDK with the same Firebase project (bondhu-a6497) and a service account key.

After the server does this, push notifications should start working for new messages.
