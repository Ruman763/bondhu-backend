# What To Do Now – Google Login Fix

Do these in order.

---

## Step 1: Put one file on your website

1. In your Bondhu project folder, open: **docs/appwrite-oauth-callback.html**
2. Copy **all** the text inside that file (Ctrl+A then Ctrl+C).
3. Log in to where **bondhu.site** (or **api.bondhu.site**) is hosted.
4. Create a **new page** so its full address is exactly:
   - **https://bondhu.site/appwrite-oauth-callback**
   (Or **https://api.bondhu.site/appwrite-oauth-callback** if you use that.)
5. Paste the code you copied into that page and **Save**.
6. In your phone browser, open that address. You should see "Redirecting to Bondhu app…". Then Step 1 is done.

---

## Step 2: Add your website in Appwrite

1. Go to **https://cloud.appwrite.io** and open your **Bondhu Super App** project.
2. Left menu → click **Auth**.
3. Top tabs → click **Settings** (or **Platforms**).
4. Click **Add platform** → choose **Web**.
5. Where it says Host or URL, type only: **bondhu.site** (or **api.bondhu.site**). No https:// and no /appwrite-oauth-callback.
6. Click Save.

---

## Step 3: Use the same URL in the app (only if you used api.bondhu.site)

- If you used **bondhu.site** in Step 1 and 2 → do nothing.
- If you used **api.bondhu.site**:
  1. Open **lib/services/appwrite_service.dart** in your project.
  2. Press Ctrl+F (or Cmd+F) and search: **oauthRedirectorUrl**
  3. Change that line to:  
     `const String _oauthRedirectorUrl = 'https://api.bondhu.site/appwrite-oauth-callback';`
  4. Save.

---

## Step 4: Run the app and test

1. In your project run: **flutter run** (or build and install the app again).
2. Open the app on your phone.
3. Tap **Sign in with Google** → choose account → tap **Continue**.

You should return to the app and be logged in.

---

## If you only use Email + Password (no Google)

- Use **Sign In** with your email and password (e.g. odritaodre9@gmail.com).
- If it stays loading, wait about 25 seconds. You should see an error like "Connection timed out" – then check your internet or try Wi‑Fi.
- Make sure in Appwrite Console → Auth → **Platforms** you have **Android** added with package name: **com.bondhu.bondhu_flutter**.
