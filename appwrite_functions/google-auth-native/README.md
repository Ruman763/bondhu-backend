# Google native auth (dedicated for app)

This Appwrite Function lets the **Flutter app** sign in with Google **without** the web redirect. The app uses native Google Sign-In, sends the ID token to this function, and gets back `userId` + `secret` to create an Appwrite session.

## 1. Create the function in Appwrite

1. **Appwrite Console** → your project → **Functions** → **Create function**.
2. Name: e.g. `google-auth-native`.
3. Runtime: **Node.js 18** (or latest).
4. **Execute** permission: set to **Any** (so the app can call it without being logged in).
5. Add **environment variables** (in the function settings):
   - `APPWRITE_ENDPOINT` = `https://backend.bondhu.site/v1` (your API endpoint)
   - `APPWRITE_PROJECT_ID` = `69cf9be50007dedee8ce`
   - `APPWRITE_API_KEY` = your **API key** with **Users** and **Auth** permissions (create key in Settings → API Keys).

## 2. Deploy the function code

- Copy the contents of `src/main.js` into the function editor (or link this folder if you use Git deploy).
- The function expects `node-appwrite` to be available (Appwrite provides it in the runtime; if not, add it in package.json).
- Deploy the function and note the **Function ID** (e.g. from the function URL or settings).

## 3. Point the Flutter app to this function

In `lib/services/appwrite_service.dart` set:

```dart
const String _nativeGoogleAuthFunctionId = 'YOUR_FUNCTION_ID';
```

Use the **Function ID** from step 2 (not the function name). Leave `_googleWebClientId` as is (your Google Web client ID).

## 4. Google Cloud

- No redirect URI is needed for this flow.
- The app uses **Google Sign-In** with your existing **Web application** client ID (`serverClientId`) so that the **ID token** is issued for your backend. The same Web client ID is fine.

## Flow

1. User taps “Sign in with Google” in the app.
2. Native Google Sign-In opens (no browser redirect).
3. App gets the Google **ID token** and POSTs it to:  
   `https://api.bondhu.site/v1/functions/{FUNCTION_ID}/executions`  
   body: `{ "idToken": "..." }`.
4. Function verifies the token with Google, finds or creates the user in Appwrite, creates a token, returns `{ "userId", "secret" }`.
5. App calls `account.createSession(userId, secret)` and then loads profile as usual.

This is **dedicated app auth**: no bondhu.site redirector, no OAuth redirect, no “Key and Secret not available” from the redirect flow.
