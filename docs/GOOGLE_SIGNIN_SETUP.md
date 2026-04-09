# Google Sign-In “Stuck Loading” Fix (Android)

After you tap **Continue** on the Google sign-in screen, the browser must redirect back to the app. If it just keeps loading, Appwrite is likely redirecting to a URL that never opens the app. Use this **redirector page** so the flow returns to the Bondhu app.

## 1. Host the redirector page

1. Use the file **`docs/appwrite-oauth-callback.html`** in this repo.
2. Host it at a URL that will be allowed by your Appwrite project, for example:
   - **https://bondhu.site/appwrite-oauth-callback**  
   or  
   - **https://api.bondhu.site/appwrite-oauth-callback**
3. The page must be served over **HTTPS** and the exact path should match the URL you use in the app (see step 3).

## 2. Add a Web platform in Appwrite Console

1. Open **Appwrite Console** → your project → **Auth** → **Settings** (or **Platforms**).
2. Click **Add platform** → **Web**.
3. Set **Host** to the origin of the redirector URL **without** the path, for example:
   - `bondhu.site`  
   or  
   - `api.bondhu.site`
4. Save.

This allows Appwrite to redirect to your redirector URL after Google sign-in.

## 3. Use the same URL in the app (if different)

The app is set to use:

- **https://bondhu.site/appwrite-oauth-callback**

If you used a different URL in step 1 (e.g. `https://api.bondhu.site/appwrite-oauth-callback`), update it in the project:

- Open **`lib/services/appwrite_service.dart`**.
- Find **`_oauthRedirectorUrl`** and set it to your full redirector URL (including path).

Example:

```dart
const String _oauthRedirectorUrl = 'https://api.bondhu.site/appwrite-oauth-callback';
```

Then rebuild and run the app.

## 4. Try Google sign-in again

1. In the app, tap **Sign in with Google**.
2. Complete the Google “Continue” step.
3. You should be sent to your redirector page, then back into the Bondhu app and signed in.

If it still sticks, check:

- The redirector URL is exactly the same in: (a) the hosted page address, (b) Appwrite Web platform host + path, (c) `_oauthRedirectorUrl` in the app.
- The redirector page is served over HTTPS and returns the HTML that redirects to `appwrite-callback-6969d933000b6cf4d826://...`.
