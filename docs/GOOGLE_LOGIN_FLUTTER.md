# Google login on Flutter app (works on website but not app)

## Option A: Dedicated app auth (recommended if redirect keeps failing)

Use **native Google Sign-In** in the app and an **Appwrite Function** that verifies the ID token and returns a session. No redirect, no bondhu.site redirector.

1. **Create and deploy the function** – See `appwrite_functions/google-auth-native/README.md`. Deploy `appwrite_functions/google-auth-native/src/main.js` as an Appwrite Function, set Execute to **Any**, add env vars (or use Appwrite’s built-in `APPWRITE_FUNCTION_*` vars).
2. **Set the function ID in the app** – In `lib/services/appwrite_service.dart` set `_nativeGoogleAuthFunctionId = 'YOUR_FUNCTION_ID';`.
3. **Google Cloud** – No redirect URI needed. Use your existing Web client ID (already in the app as `_googleWebClientId`).

After that, the app will use native Google Sign-In and the function; only if that fails (e.g. function not deployed) will it fall back to the OAuth redirect flow.

---

## Option B: OAuth redirect (website-style flow)

Google login works on the **website** because the site uses the same origin as the redirect (`window.location.href`). On the **Flutter app** (Android/iOS), the flow uses an HTTPS redirector page that then opens the app via a custom URL scheme. If that redirect URL is not allowed in Appwrite, or the redirector is missing, login will fail.

## Checklist

### 1. Appwrite Console – allow the redirect URL hostname

Appwrite only accepts `success` and `failure` URLs whose **hostname** is in your project’s **platform list**.

- Open your Appwrite project → **Auth** → **Settings** (or **Overview** → **Platforms**).
- Ensure you have a **Web** platform whose hostname is **`bondhu.site`** (no trailing slash, no path).
- If your site is `www.bondhu.site`, add that hostname instead.
- The redirect URL used by the Flutter app is:  
  `https://bondhu.site/appwrite-oauth-callback`  
  So the hostname `bondhu.site` must be in the platform list. Adding a Web platform with hostname `bondhu.site` is enough.

### 2. Redirector page must be live

The Flutter app sends users to:

`https://bondhu.site/appwrite-oauth-callback`

after Google sign-in. That URL must serve a page that:

- Reads the query string or fragment (e.g. `?key=...&secret=...` or `#key=...&secret=...`).
- Redirects the browser to:  
  `appwrite-callback-6969d933000b6cf4d826://callback?...`  
  (same query/fragment), so the app can receive the callback.

Ensure:

- The site is deployed and `https://bondhu.site/appwrite-oauth-callback` returns the redirector page (not 404).
- If you use Vue Router, the route `/appwrite-oauth-callback` must render the component that does the redirect (see `bondhu-v2`’s `AppwriteOAuthCallback.vue` and `public/appwrite-oauth-callback.html`).

### 3. Google Cloud Console – what to add or update

Google must send the user back to **Appwrite’s** URL after sign-in, not to your app or website. Use the same OAuth client for both website and Flutter app.

**Step 1 – Get the exact redirect URI from Appwrite**

1. Open **Appwrite Console** → your project → **Auth** → **Settings**.
2. Open the **Google** provider (or add it).
3. In the OAuth2 settings you’ll see a **URI** (redirect URL) to copy. It looks like:
   - Cloud: `https://sgp.cloud.appwrite.io/v1/account/sessions/oauth2/callback/google/`
   - Self-hosted: `https://api.bondhu.site/v1/account/sessions/oauth2/callback/google` (or similar)
4. Copy that URL **exactly** from the Appwrite modal (including trailing slash if present).

**Step 2 – Add it in Google Cloud Console**

1. Go to [Google Cloud Console](https://console.cloud.google.com/) → select your project (or create one).
2. **APIs & Services** → **Credentials**.
3. Click your **OAuth 2.0 Client ID** (type **Web application**).  
   - If you don’t have one: **+ Create Credentials** → **OAuth client ID** → Application type: **Web application**.
4. Under **Authorized redirect URIs**:
   - Click **+ ADD URI**.
   - Paste the Appwrite URL from Step 1, e.g. `https://sgp.cloud.appwrite.io/v1/account/sessions/oauth2/callback/google/` or your host’s equivalent.
   - Do **not** add `https://bondhu.site/appwrite-oauth-callback` here; that’s only for Appwrite → app, not for Google.
5. Under **Authorized JavaScript origins** (if present):
   - Add `https://bondhu.site` (your website).
   - Add `https://api.bondhu.site` (your Appwrite API host).
6. Click **Save**.

**Step 3 – Use the same credentials in Appwrite**

- In Appwrite Console → Auth → Google provider, set **Client ID** and **Client Secret** to the values from this same OAuth client in Google Cloud.
- Enable the Google provider (toggle on).

**Common mistakes**

- Adding the wrong redirect URI (e.g. bondhu.site instead of api.bondhu.site).
- Using an **Android** or **iOS** client for the Flutter app: with Appwrite, the flow goes through your server, so the **Web application** client and the Appwrite callback URL above are correct for the Flutter app too.
- Typo or trailing slash in the redirect URI (must match exactly what Appwrite shows).

### 4. Android / iOS

- **Android**: `AndroidManifest.xml` already has the `CallbackActivity` for `appwrite-callback-6969d933000b6cf4d826` (see `android/app/src/main/AndroidManifest.xml`).
- **iOS**: `Info.plist` already has the URL scheme `appwrite-callback-6969d933000b6cf4d826`.

No code change needed there unless you use a different project ID.

## Quick test

1. On the device/emulator, tap “Sign in with Google” in the Flutter app.
2. Complete Google sign-in in the browser.
3. You should be redirected to `https://bondhu.site/appwrite-oauth-callback?...`.
4. That page should immediately redirect to `appwrite-callback-6969d933000b6cf4d826://...` and the app should open, logged in.

If step 3 shows 404 or a blank page, fix the redirector deployment. If step 3 loads but step 4 never happens, check the redirector script (fragment vs query, correct scheme). If Appwrite returns an error when starting the OAuth flow, add `bondhu.site` (or the correct hostname) as a Web platform in Appwrite.

---

## Still not working? (“Key and Secret not available”)

1. **Use the same Appwrite project as the app**  
   The Flutter app uses **`https://api.bondhu.site/v1`**. So:
   - In **Appwrite** you must configure the project that serves **api.bondhu.site** (not a different cloud project).
   - In that project: add **bondhu.site** as a Web platform, and set Google provider with the same Client ID/Secret as in Google Cloud.
   - In **Google Cloud**, **Authorized redirect URIs** must include:  
     `https://api.bondhu.site/v1/account/sessions/oauth2/callback/google`  
     (or the exact URI shown in that Appwrite project’s Google OAuth2 settings).

2. **Redirector must send params in the query and include `key`**  
   The redirector at `https://bondhu.site/appwrite-oauth-callback` must:
   - Convert **fragment** (`#userId=...&secret=...`) to **query** (`?userId=...&secret=...`).
   - If the URL has `userId` but no `key`, add `key=<userId>` (the Flutter SDK often expects `key` and `secret`).
   - Then redirect to:  
     `appwrite-callback-6969d933000b6cf4d826://callback?key=...&secret=...`  
   The bondhu-v2 repo has this logic in `AppwriteOAuthCallback.vue` and `public/appwrite-oauth-callback.html`. Redeploy the site after any change.

3. **Confirm the redirector is the one that runs**  
   If your server serves a static file at `/appwrite-oauth-callback`, that file is used. If the Vue app handles that route, the Vue component is used. In both cases the logic above (fragment → query, add `key` from `userId`) must be present. Rebuild and deploy bondhu-v2 after editing either file.
