/**
 * Appwrite Function: Google native auth (dedicated for app).
 * Receives Google ID token from the Flutter app, verifies it with Google,
 * finds or creates the user in Appwrite, creates a session token, returns { userId, secret }.
 *
 * Deploy: Appwrite Console → Functions → Create function → Node.js 18 → paste this code.
 * Set Execute permission to "Any" so the app can call without being logged in.
 * Add env vars: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY (with Users + Auth permissions).
 */

const { Client, Users, Query } = require('node-appwrite');
const crypto = require('crypto');

function makeSafeUserId() {
  // Appwrite userId must be <=36 and contain only [a-zA-Z0-9._-]
  // Use a stable safe prefix + UUID without dashes.
  const raw = crypto.randomUUID().replace(/-/g, '');
  return `u_${raw}`.slice(0, 36);
}

function isSafeUserId(value) {
  if (!value || typeof value !== 'string') return false;
  if (value.length > 36) return false;
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value)) return false;
  return true;
}

async function createUserCompat(users, { userId, email, name }) {
  // Appwrite JS SDK signatures differ across versions.
  // Try positional args first, then object payload fallback.
  try {
    return await users.create(userId, email, undefined, undefined, name);
  } catch (_) {
    return await users.create({ userId, email, name });
  }
}

module.exports = async ({ req, res, log, error }) => {
  if (req.method !== 'POST') {
    return res.json({ error: 'Method not allowed' }, 405);
  }

  let body = req.body;
  if (typeof body === 'string' && body.trim().length > 0) {
    try {
      body = JSON.parse(body);
    } catch (_) {
      body = {};
    }
  }
  if (!body || typeof body !== 'object') {
    body = {};
  }

  const idToken = body.idToken ?? body.id_token;
  if (!idToken || typeof idToken !== 'string') {
    return res.json({ error: 'Missing idToken' }, 400);
  }

  try {
    // 1. Verify Google ID token
    const tokenRes = await fetch(
      `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`
    );
    if (!tokenRes.ok) {
      error('Google token verification failed: ' + (await tokenRes.text()));
      return res.json({ error: 'Invalid Google token' }, 401);
    }
    const payload = await tokenRes.json();
    const email = (payload.email || '').trim().toLowerCase();
    const name = (payload.name || payload.given_name || email.split('@')[0] || 'User').trim();
    if (!email) {
      return res.json({ error: 'No email in token' }, 400);
    }

    const endpoint = process.env.APPWRITE_ENDPOINT || process.env.APPWRITE_FUNCTION_API_ENDPOINT;
    const projectId = process.env.APPWRITE_PROJECT_ID || process.env.APPWRITE_FUNCTION_PROJECT_ID;
    const apiKey = process.env.APPWRITE_API_KEY || process.env.APPWRITE_FUNCTION_API_KEY;
    if (!endpoint || !projectId || !apiKey) {
      error('Missing APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, or APPWRITE_API_KEY');
      return res.json({ error: 'Server configuration error' }, 500);
    }

    const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
    const users = new Users(client);

    // 2. Find existing user by email (same project)
    const list = await users.list([Query.equal('email', email)]);
    let userId = null;
    if (Array.isArray(list.users) && list.users.length > 0) {
      // Prefer a valid/safe userId if multiple users are returned.
      const safeExisting = list.users.find((u) => isSafeUserId(u?.$id));
      if (safeExisting?.$id) {
        userId = safeExisting.$id;
      } else {
        // Legacy invalid IDs found for this email; ignore and recreate safely.
        log(`No safe userId found for ${email}; will create a fresh auth user`);
      }
    }

    if (!userId) {
      // 3. Create user (profile is keyed by email in DB; Appwrite user $id can be unique)
      const created = await createUserCompat(users, {
        userId: makeSafeUserId(),
        email,
        name,
      });
      userId = created.$id;
      log('Created user: ' + userId);
    }

    // 4. Create session token (short-lived; client exchanges for session)
    // Some old/legacy users may have invalid ID format for token generation.
    // If that happens, recreate the auth user with a clean ID and retry once.
    let token;
    try {
      token = await users.createToken(userId);
    } catch (createTokenError) {
      const msg = String(createTokenError?.message || createTokenError || '').toLowerCase();
      const isLegacyIdError =
        msg.includes("invalid 'userid' param") || msg.includes('invalid user id');
      if (!isLegacyIdError) throw createTokenError;

      log(`Legacy userId detected for ${email}; recreating auth user`);
      try {
        await users.delete(userId);
      } catch (deleteErr) {
        error(`Failed to delete legacy user ${userId}: ${String(deleteErr)}`);
        throw createTokenError;
      }

      const recreated = await createUserCompat(users, {
        userId: makeSafeUserId(),
        email,
        name,
      });
      userId = recreated.$id;
      token = await users.createToken(userId);
    }
    return res.json({ userId, secret: token.secret });
  } catch (err) {
    error(String(err));
    return res.json({ error: err.message || 'Auth failed' }, 500);
  }
};
