# Connect Bondhu Flutter app to Appwrite (full database setup)

Your Flutter app uses the **same** Appwrite project and database as your website (bondhu-v2).

---

## 1. Appwrite config (already in the app)

| Setting | Value (used in Flutter) |
|--------|--------------------------|
| Endpoint | `https://api.bondhu.site/v1` |
| Project ID | `6969d933000b6cf4d826` |
| Database ID | `bondhu_db` |
| Bucket (Media) | `Media` |

These match the website. No code change needed.

---

## 2. Collections the app uses

Create these collections inside database **bondhu_db** in Appwrite Console. Set **permissions** so your app (or “Users” role) can Create, Read, Update, Delete where needed.

### profiles

| Attribute | Type | Required | Notes |
|-----------|------|----------|--------|
| userId | string | yes | User email (lowercase) |
| name | string | yes | Display name |
| avatar | string | no | URL |
| bio | string | no | |
| location | string | no | |
| followers | string | no | JSON array string, max 255 chars |
| following | string | no | JSON array string, max 255 chars |
| publicKey | string | no | For E2E (optional) |
| contactList | string | no | JSON array string (legacy) |
| **fcmToken** | **string** | **no** | **FCM device token for push notifications. App writes this when user logs in on a device. Required for push.** |

Used for: login sync, Contact page, New Group members, profile view, feed, **push notifications (fcmToken)**.

---

### friend_requests

| Attribute | Type | Required | Notes |
|-----------|------|----------|--------|
| fromUserId | string | yes | Sender email (lowercase) |
| toUserId | string | yes | Recipient email (lowercase) |
| status | string | yes | `pending` \| `accepted` \| `declined` |
| createdAt | integer | no | Milliseconds (e.g. Date.now()) |

Used for: Private chat → send friend request, Contact page (Contacts + Requests tabs), Accept/Decline, New Group (contacts = accepted friends).

Permissions: **Create** (so users can send requests), **Read** (list incoming/outgoing and contacts), **Update** (accept/decline).

Indexes (recommended in Appwrite Console → friend_requests → Indexes):  
- `toUserId` + `status` (for incoming pending),  
- `fromUserId` (for outgoing and contacts).

---

### posts

| Attribute | Type | Notes |
|-----------|------|--------|
| userId | string | Author email |
| content | string | |
| mediaUrl | string | |
| type | string | e.g. text, image |
| likesList | array | String IDs |
| savedBy | array | String IDs |
| comments | array | Comment objects |
| timestamp | string | ISO date |

Used for: Feed.

---

### stories

| Attribute | Type | Notes |
|-----------|------|--------|
| userId | string | |
| mediaUrl | string | |
| timestamp | integer | Milliseconds |
| likes | array | |
| views | array | |
| comments | array | |

Used for: Stories (24h).

---

## 3. What the app does with the database

| Feature | Collection | Action |
|---------|------------|--------|
| Login / sync profile | profiles | Create or read by userId |
| Update profile (name, avatar, bio) | profiles | Update |
| Contact list (friends) | friend_requests | Read where status = accepted |
| Send friend request (Private → email) | friend_requests | Create (fromUserId, toUserId, status: pending) |
| Incoming requests (Contacts → Requests) | friend_requests | Read toUserId = me, status = pending |
| Outgoing requests | friend_requests | Read fromUserId = me |
| Accept / Decline request | friend_requests | Update status to accepted / declined |
| New Group (list members) | friend_requests + profiles | Contacts = accepted; then getProfilesByIds |
| Feed | posts | List, create, like, comment |
| Stories | stories | Create, list, delete |

---

## 4. Website vs app (friend requests)

- **Flutter app** uses collection **friend_requests** with attributes **fromUserId**, **toUserId**, **status**, **createdAt** (integer).
- **Website (bondhu-v2)** uses **chat_requests** with **from**, **to**, **status**, **firstMessage**, **createdAt** (string).

So today the app and website use **different collections** for requests. Your “friend requests” table in Appwrite should be the one the app uses:

- **Collection ID:** `friend_requests`
- **Attributes:** fromUserId (string), toUserId (string), status (string), createdAt (integer)

If you created this collection and permissions as above, the app is already fully connected to the database for friend requests, contacts, profiles, posts, and stories.

---

## 5. Quick checklist

- [ ] Database **bondhu_db** exists.
- [ ] Collection **profiles** exists with attributes above (and index on `userId` if you use Query.equal).
- [ ] Collection **friend_requests** exists with **fromUserId**, **toUserId**, **status**, **createdAt**.
- [ ] Permissions on **friend_requests**: Create, Read, Update for your app/users.
- [ ] Collections **posts** and **stories** exist if you use Feed and Stories.
- [ ] For push: add **fcmToken** (string, optional) to **profiles** in Appwrite; Firebase configured.

After this, the app is fully connected to the database; no extra “connection” code is needed.
