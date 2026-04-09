# Appwrite: Friend requests collection setup

If you see an error when sending a friend request from the **Private** option (e.g. "Couldn't send friend request"), the app is trying to create a document in Appwrite. You need a collection named **friend_requests** in your database.

## 1. Create the collection

In [Appwrite Console](https://cloud.appwrite.com) → your project → **Databases** → your database (e.g. `bondhu_db`) → **Create collection**.

- **Name:** `friend_requests`
- **Collection ID:** `friend_requests` (must match the app: see `_collFriendRequests` in `lib/services/appwrite_service.dart`)

## 2. Add attributes

Create these attributes (type and size as below):

| Attribute ID   | Type   | Size  | Required |
|----------------|--------|-------|----------|
| fromUserId     | string | 255   | yes      |
| toUserId       | string | 255   | yes      |
| status         | string | 20    | yes      |
| createdAt      | integer| -     | no       |

- **status** values used by the app: `pending`, `accepted`, `declined`.

## 3. Permissions

Set **create** permission so your app (or users) can create documents when sending a friend request.  
Set **read** and **update** so users can list and accept/decline requests.

Example (simplified): allow anyone in the project to create and read documents in this collection, and update only their own (you can refine with Appwrite roles).

Without this collection and permissions, "Send friend request" will fail and the app will show: *"Couldn't send friend request. Check the email and try again."*
