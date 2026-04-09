# Follow / Unfollow and Appwrite Permissions

When a user taps **Follow** on someone else's profile, the app must update two profile documents:

1. **Your profile** – add/remove them from your `following` list (you have permission).
2. **Their profile** – add/remove yourself from their `followers` list (requires permission to write their document).

If the Appwrite **profiles** collection allows only the document owner to update, the second update fails. The app still updates your profile and shows "Following", but their follower count will not change.

## Option A: Collection permissions (simplest)

In **Appwrite Console** → your project → **Databases** → **bondhu_db** → **profiles**:

1. Open **Settings** (or the collection’s permissions).
2. Under **Update** permission, add role **Users** (all authenticated users).

Then any logged-in user can update any profile document, so both follow updates succeed from the client.

## Option B: Follow Cloud Function

Keep strict document permissions and use a Cloud Function to perform both updates with server (admin) access:

1. Create an Appwrite Function that:
   - Accepts body: `{ "myEmail": "...", "theirUserId": "...", "follow": true|false }`.
   - Uses the **Server SDK** (with API key) to update both profile documents (your `following`, their `followers`).
2. Deploy the function and note its **Function ID**.
3. In the Flutter app, set the follow function ID in `lib/services/appwrite_service.dart`:

   ```dart
   const String _followFunctionId = 'YOUR_FOLLOW_FUNCTION_ID';
   ```

The app will call this function when it’s set; otherwise it uses direct client updates (your profile first, then theirs, with a fallback message if theirs fails).
