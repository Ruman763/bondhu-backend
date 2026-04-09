# Appwrite self-hosted schema (Bondhu Flutter)

Reference for recreating **database `bondhu_db`**, **collections**, **attribute sizes**, and **indexes** when moving from Appwrite Cloud to self-hosted. Derived from `lib/services/appwrite_service.dart` (same IDs as bondhu-v2 web where applicable).

**Constants in code**

| Item | ID / value |
|------|------------|
| Database | `bondhu_db` |
| Storage bucket | `Media` |
| Collection profiles | `profiles` |
| Collection posts | `posts` |
| Collection stories | `stories` |
| Collection call logs | `call_logs` |
| Collection messages | `messages` |
| Collection queue | `queued_messages` |
| Collection chat requests | `chat_requests` |
| Collection chat migrations | `chat_migrations` |

---

## String size notes (Appwrite)

- Appwrite **string** attributes have a **max length** you set at creation (e.g. 255 … 1,073,741,824 on recent versions). Pick at least the **minimum** below; increase if you hit write errors.
- Prefer **String array** (`string[]`) for `followers`, `following`, `contactList`, `likesList`, `savedBy` when possible so you are not limited to 255 chars of JSON (the app sends JSON arrays from Dart).
- If you store `contactList` as a **single string** of JSON, the app’s `contactListToString()` **truncates to 255 characters** — large contact lists will break. Use **`string[]`** for `contactList` in self-hosted.

---

## 1. Collection `profiles`

| Attribute | Type | Recommended max size | Required | Notes |
|-----------|------|----------------------|----------|--------|
| `userId` | string | **255** | yes | Lowercase email; unique per user. **Index:** unique or key on `userId`. |
| `name` | string | **128** | yes | Display name |
| `avatar` | string | **2048** | no | Storage file ID or full URL (app builds view URL) |
| `bio` | string | **4096** | no | |
| `location` | string | **256** | no | |
| `followers` | string[] | (default) | no | List of user IDs (emails). **Index** optional for lookups. |
| `following` | string[] | (default) | no | Same |
| `contactList` | string[] | (default) | no | **Prefer array**, not a single JSON string |
| `publicKey` | string | **4096** | no | RSA public JWK for E2E |
| `e2eBackup` | string | **65535**–**131072** | no | Base64-wrapped encrypted private key backup; needs room for growth |
| `e2eBackupSalt` | string | **128** | no | Base64 salt |
| `e2eBackupIterations` | string | **32** | no | KDF iteration count as string (e.g. `200000`) |
| `messageCryptoSalt` | string | **128** | no | Base64 random salt for PBKDF2; used with login password to derive the AES key for encrypted rows in `messages` |
| `audienceProfiles` | string | **16384** | no | JSON map of audience → `{name,bio,avatar}`; app may `jsonEncode` on update |
| `fcmToken` | string | **512** | no | FCM registration token for push |

**Recommended indexes**

- `userId` — **key** (queries: `Query.equal('userId', …)`).
- `name` — **fulltext** (optional; `Query.search` in `searchProfiles`).
- `userId` prefix — **key** (optional; `Query.startsWith('userId', …)`).

---

## 2. Collection `posts`

| Attribute | Type | Recommended max size | Required | Notes |
|-----------|------|----------------------|----------|--------|
| `userId` | string | **255** | yes | Author email |
| `content` | string | **65535** | yes | Post body (raise if long posts) |
| `mediaUrl` | string | **2048** | no | File ID or URL |
| `type` | string | **32** | yes | e.g. `text`, `image` |
| `likesList` | string[] | (default) | no | User IDs |
| `savedBy` | string[] | (default) | no | User IDs |
| `comments` | string[] | (default) | no | App supports list of maps or JSON strings |
| `timestamp` | string | **64** | yes | ISO-8601 (`DateTime.now().toIso8601String()`) |

**Recommended indexes**

- `$createdAt` — order desc for feed (`getPosts`).

---

## 3. Collection `stories`

| Attribute | Type | Recommended max size | Required | Notes |
|-----------|------|----------------------|----------|--------|
| `userId` | string | **255** | yes | |
| `mediaUrl` | string | **2048** | yes | |
| `timestamp` | integer | — | yes | Milliseconds since epoch |
| `likes` | string[] | (default) | no | Optional; app reads if present |
| `views` | string[] | (default) | no | Optional |
| `comments` | string[] | (default) | no | Optional |

**Recommended indexes**

- `$createdAt` — for listing recent stories.

---

## 4. Collection `call_logs`

| Attribute | Type | Recommended max size | Required | Notes |
|-----------|------|----------------------|----------|--------|
| `callerId` | string | **255** | yes | Email / user id |
| `receiverId` | string | **255** | yes | |
| `type` | string | **32** | yes | e.g. audio / video |
| `duration` | integer | — | yes | Seconds (or ms — app sends `int`) |
| `timestamp` | string | **64** | yes | ISO-8601 |

---

## 5. Collection `messages` (encrypted cloud backup)

Used when message sync is on (default): stores **ciphertext** per chat direction. **`bms3:`** payloads use a random device vault key (not stored in the database). Legacy **`bms2:`** rows use AES-GCM with a key derived from login password + `messageCryptoSalt`. Older rows may use RSA self-encryption (E2E JWK).

| Attribute | Type | Recommended max size | Required | Notes |
|-----------|------|----------------------|----------|--------|
| `senderId` | string | **255** | yes | Lowercase email |
| `receiverId` | string | **255** | yes | Lowercase email / chat id |
| `text` | string | **65535** | yes | Encrypted payload (base64 JSON); must be large |
| `timestamp` | string | **64** | yes | ISO-8601; used for ordering |

**Recommended indexes**

- Composite: `senderId` + `receiverId` + `timestamp` (for `getChatHistory` queries).

---

## 5a. Collection `chat_migrations` (QR chat-key migration)

Short-lived documents for **WeChat-style** transfer of message decryption keys. The **QR carries a random token**; the server only stores **ciphertext** of the key bundle. A DB leak without the QR token does not reveal keys.

| Attribute | Type | Recommended max size | Required | Notes |
|-----------|------|----------------------|----------|--------|
| `userId` | string | **255** | yes | Lowercase email; must match the signed-in user |
| `cipher` | string | **65535** | yes | Opaque sealed payload from the app |
| `expiresAt` | string | **64** | yes | ISO-8601 UTC; app rejects expired rows |

**Permissions:** authenticated users can **create**; **read/delete** only documents where `userId` matches their session (or use a Function). Optional: scheduled cleanup of expired docs.

---

## 6. Collection `queued_messages`

Offline / store-and-forward queue.

| Attribute | Type | Recommended max size | Required | Notes |
|-----------|------|----------------------|----------|--------|
| `recipient` | string | **255** | yes | Lowercase email |
| `senderId` | string | **255** | yes | |
| `senderName` | string | **128** | no | |
| `payload` | string | **65535** | yes | Message body |
| `msgId` | string | **128** | no | Client message id |
| `type` | string | **32** | no | e.g. `text` |
| `timestamp` | string | **64** | yes | ISO-8601 |

**Recommended indexes**

- `recipient` — **key** (`getQueuedMessages`).

---

## 7. Collection `chat_requests`

Flutter app uses **`chat_requests`** with **`from` / `to`** (not `friend_requests` / `fromUserId`).

| Attribute | Type | Recommended max size | Required | Notes |
|-----------|------|----------------------|----------|--------|
| `from` | string | **255** | yes | Sender email |
| `to` | string | **255** | yes | Recipient email |
| `status` | string | **32** | yes | `pending`, `accepted`, `declined`, `cancelled` |
| `firstMessage` | string | **512** | no | App truncates to **500** chars on create |
| `createdAt` | string | **64** | no | ISO-8601 |

**Recommended indexes**

- `to` + `status` — incoming pending (`getPendingRequestsForUser`, counts).
- `from` + `status` — outgoing pending (`getSentRequestsForUser`).
- `from` + `to` — `getRequestBetween`.

---

## 8. Storage bucket `Media`

- **Bucket ID:** `Media` (must match `appwrite_service.dart` `_bucketId`).
- Files uploaded with **read permission** `Role.any()` for public view URLs.
- App builds URLs as:  
  `{endpoint}/storage/buckets/Media/files/{fileId}/view?project={projectId}`

After self-hosting, set **endpoint** and **project ID** in the app config to match your server.

---

## 9. Permissions (typical)

Tune to your security model; common pattern:

- **profiles:** users can **read** many profiles (search/directory), **create/update** own document (match `userId` to session) — often implemented with collection rules or a small API layer on self-hosted.
- **posts / stories:** authenticated **create**; **read** as needed (public vs users).
- **messages / queued_messages / call_logs / chat_requests:** restrict so users only read/write rows involving their `userId` / email (Appwrite permissions or Functions).

---

## 10. Optional Cloud Functions (IDs in code)

| Env / constant | Purpose |
|----------------|--------|
| `auth_app` (`_nativeGoogleAuthFunctionId`) | Native Google → Appwrite session |
| `_followFunctionId` (empty = disabled) | Server-side follow/unfollow |

These are **not** database tables; deploy separately on self-hosted Appwrite.

---

## 11. Migration checklist (Cloud → self-hosted)

1. Create **database** `bondhu_db`.
2. Create collections and attributes with sizes **≥** tables above.
3. Add **indexes** for `userId`, `recipient`, chat request queries, post ordering.
4. Create bucket **Media** and CORS / allowed origins for your web app.
5. Copy **documents** (or export/import JSON) from Cloud if migrating data.
6. Update Flutter **endpoint** and **project ID** to self-hosted values.
7. Re-create **API keys**, **OAuth** (Google) redirect URLs, and **platforms** (Web, iOS, Android).
8. Test: login, profile sync, feed, story, chat backup (`e2eBackup*` attributes), message sync (`messages` collection).

---

## 12. Legacy doc note

`docs/APPWRITE_FULL_SETUP.md` mentions **`friend_requests`** / `fromUserId` — the **current Flutter client** uses **`chat_requests`** with **`from`** and **`to`**. Align new self-hosted projects with **this** document for the app in this repo.
