const express = require('express');
const bcrypt = require('bcryptjs');
const { OAuth2Client } = require('google-auth-library');
const { z } = require('zod');
const crypto = require('crypto');
const db = require('../db');
const {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} = require('../utils/jwt');
const { createRateLimiter } = require('../middleware/rateLimit');
const { sendPasswordResetEmail } = require('../utils/mailer');

const router = express.Router();
const googleClient = new OAuth2Client(process.env.GOOGLE_CLIENT_ID || undefined);

const signupSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6),
  name: z.string().min(1).max(120).optional(),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

const googleSchema = z.object({
  idToken: z.string().min(1),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

const forgotPasswordSchema = z.object({
  email: z.string().email(),
});

const resetPasswordSchema = z.object({
  token: z.string().min(20),
  newPassword: z.string().min(6),
});

const loginLimiter = createRateLimiter({
  keyPrefix: 'auth-login',
  windowMs: 15 * 60 * 1000,
  max: 10,
  keyGenerator: (req) => {
    const email = String(req.body?.email || '').trim().toLowerCase();
    return `${req.ip}:${email || 'unknown'}`;
  },
});

const signupLimiter = createRateLimiter({
  keyPrefix: 'auth-signup',
  windowMs: 15 * 60 * 1000,
  max: 5,
  keyGenerator: (req) => {
    const email = String(req.body?.email || '').trim().toLowerCase();
    return `${req.ip}:${email || 'unknown'}`;
  },
});

const forgotLimiter = createRateLimiter({
  keyPrefix: 'auth-forgot-password',
  windowMs: 15 * 60 * 1000,
  max: 5,
  keyGenerator: (req) => {
    const email = String(req.body?.email || '').trim().toLowerCase();
    return `${req.ip}:${email || 'unknown'}`;
  },
});

const resetLimiter = createRateLimiter({
  keyPrefix: 'auth-reset-password',
  windowMs: 15 * 60 * 1000,
  max: 10,
});

function authResponse(user) {
  const accessToken = signAccessToken(user);
  const { token, tokenHash, refreshDays } = signRefreshToken(user);
  return {
    accessToken,
    refreshToken: token,
    refreshTokenHash: tokenHash,
    refreshDays,
  };
}

async function saveRefreshToken(userId, tokenHash, refreshDays) {
  await db.query(
    `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
     VALUES ($1, $2, NOW() + ($3 || ' days')::interval)`,
    [userId, tokenHash, String(refreshDays)]
  );
}

async function buildUserPayload(userId) {
  const result = await db.query(
    `SELECT u.id, u.email, p.display_name, p.avatar_url
     FROM users u
     LEFT JOIN profiles p ON p.user_id = u.id
     WHERE u.id = $1`,
    [userId]
  );
  return result.rows[0];
}

router.post('/signup', signupLimiter, async (req, res) => {
  const parsed = signupSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  const { email, password, name } = parsed.data;
  const normalizedEmail = email.trim().toLowerCase();

  try {
    const existing = await db.query('SELECT id FROM users WHERE email = $1', [normalizedEmail]);
    if (existing.rowCount > 0) {
      return res.status(409).json({ error: 'Email already exists' });
    }

    const passwordHash = await bcrypt.hash(password, 12);

    const userInsert = await db.query(
      `INSERT INTO users (email, password_hash, auth_provider)
       VALUES ($1, $2, 'email')
       RETURNING id, email`,
      [normalizedEmail, passwordHash]
    );
    const user = userInsert.rows[0];

    await db.query(
      `INSERT INTO profiles (user_id, display_name)
       VALUES ($1, $2)`,
      [user.id, name || normalizedEmail.split('@')[0]]
    );

    const tokenPayload = authResponse(user);
    await saveRefreshToken(user.id, tokenPayload.refreshTokenHash, tokenPayload.refreshDays);
    const userPayload = await buildUserPayload(user.id);

    return res.status(201).json({
      user: userPayload,
      accessToken: tokenPayload.accessToken,
      refreshToken: tokenPayload.refreshToken,
    });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to sign up' });
  }
});

router.post('/login', loginLimiter, async (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  const { email, password } = parsed.data;
  const normalizedEmail = email.trim().toLowerCase();

  try {
    const result = await db.query(
      'SELECT id, email, password_hash FROM users WHERE email = $1',
      [normalizedEmail]
    );

    if (result.rowCount === 0) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const user = result.rows[0];
    if (!user.password_hash) {
      return res.status(400).json({ error: 'This account uses social login' });
    }

    const ok = await bcrypt.compare(password, user.password_hash);
    if (!ok) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const tokenPayload = authResponse(user);
    await saveRefreshToken(user.id, tokenPayload.refreshTokenHash, tokenPayload.refreshDays);
    const userPayload = await buildUserPayload(user.id);

    return res.json({
      user: userPayload,
      accessToken: tokenPayload.accessToken,
      refreshToken: tokenPayload.refreshToken,
    });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to log in' });
  }
});

router.post('/google', async (req, res) => {
  const parsed = googleSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  if (!process.env.GOOGLE_CLIENT_ID) {
    return res.status(400).json({ error: 'Google login not configured on server' });
  }

  try {
    const ticket = await googleClient.verifyIdToken({
      idToken: parsed.data.idToken,
      audience: process.env.GOOGLE_CLIENT_ID,
    });
    const payload = ticket.getPayload();
    const email = (payload.email || '').trim().toLowerCase();
    const displayName = payload.name || email.split('@')[0];
    const avatarUrl = payload.picture || null;

    if (!email) {
      return res.status(400).json({ error: 'Google token did not include email' });
    }

    let userResult = await db.query('SELECT id, email FROM users WHERE email = $1', [email]);
    let user = userResult.rows[0];

    if (!user) {
      const insert = await db.query(
        `INSERT INTO users (email, auth_provider)
         VALUES ($1, 'google')
         RETURNING id, email`,
        [email]
      );
      user = insert.rows[0];
      await db.query(
        `INSERT INTO profiles (user_id, display_name, avatar_url)
         VALUES ($1, $2, $3)`,
        [user.id, displayName, avatarUrl]
      );
    } else {
      await db.query(
        `UPDATE profiles
         SET display_name = COALESCE(display_name, $2),
             avatar_url = COALESCE(avatar_url, $3)
         WHERE user_id = $1`,
        [user.id, displayName, avatarUrl]
      );
    }

    const tokenPayload = authResponse(user);
    await saveRefreshToken(user.id, tokenPayload.refreshTokenHash, tokenPayload.refreshDays);
    const userPayload = await buildUserPayload(user.id);

    return res.json({
      user: userPayload,
      accessToken: tokenPayload.accessToken,
      refreshToken: tokenPayload.refreshToken,
    });
  } catch (error) {
    return res.status(401).json({ error: 'Invalid Google token' });
  }
});

router.post('/refresh', async (req, res) => {
  const parsed = refreshSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  try {
    const decoded = verifyRefreshToken(parsed.data.refreshToken);
    const tokenHash = crypto.createHash('sha256').update(parsed.data.refreshToken).digest('hex');

    const tokenResult = await db.query(
      `SELECT id, user_id, revoked_at, expires_at
       FROM refresh_tokens
       WHERE token_hash = $1`,
      [tokenHash]
    );

    if (tokenResult.rowCount === 0) {
      return res.status(401).json({ error: 'Refresh token not recognized' });
    }

    const tokenRow = tokenResult.rows[0];
    if (tokenRow.revoked_at || new Date(tokenRow.expires_at) <= new Date()) {
      return res.status(401).json({ error: 'Refresh token expired or revoked' });
    }

    if (tokenRow.user_id !== decoded.sub) {
      return res.status(401).json({ error: 'Refresh token user mismatch' });
    }

    await db.query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE id = $1', [tokenRow.id]);

    const userResult = await db.query('SELECT id, email FROM users WHERE id = $1', [decoded.sub]);
    if (userResult.rowCount === 0) {
      return res.status(401).json({ error: 'User not found' });
    }

    const user = userResult.rows[0];
    const tokenPayload = authResponse(user);
    await saveRefreshToken(user.id, tokenPayload.refreshTokenHash, tokenPayload.refreshDays);

    return res.json({
      accessToken: tokenPayload.accessToken,
      refreshToken: tokenPayload.refreshToken,
    });
  } catch (error) {
    return res.status(401).json({ error: 'Invalid refresh token' });
  }
});

router.post('/logout', async (req, res) => {
  const parsed = refreshSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  try {
    const tokenHash = crypto.createHash('sha256').update(parsed.data.refreshToken).digest('hex');
    await db.query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = $1', [tokenHash]);
    return res.json({ ok: true });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to logout' });
  }
});

router.post('/forgot-password', forgotLimiter, async (req, res) => {
  const parsed = forgotPasswordSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  const normalizedEmail = parsed.data.email.trim().toLowerCase();
  const resetBaseUrl =
    process.env.PASSWORD_RESET_URL_BASE || process.env.APP_BASE_URL || 'http://localhost:3000/reset-password';

  try {
    const userResult = await db.query('SELECT id, email FROM users WHERE email = $1', [normalizedEmail]);
    if (userResult.rowCount === 0) {
      // Avoid email enumeration leaks.
      return res.json({ ok: true, message: 'If this email exists, a reset link has been sent.' });
    }

    const user = userResult.rows[0];
    const rawToken = crypto.randomBytes(32).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');

    await db.query(
      `UPDATE password_reset_tokens
       SET used_at = NOW()
       WHERE user_id = $1 AND used_at IS NULL AND expires_at > NOW()`,
      [user.id]
    );

    await db.query(
      `INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
       VALUES ($1, $2, NOW() + INTERVAL '30 minutes')`,
      [user.id, tokenHash]
    );

    const separator = resetBaseUrl.includes('?') ? '&' : '?';
    const resetLink = `${resetBaseUrl}${separator}token=${encodeURIComponent(rawToken)}`;
    await sendPasswordResetEmail(user.email, resetLink);

    return res.json({ ok: true, message: 'If this email exists, a reset link has been sent.' });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to process forgot-password request' });
  }
});

router.post('/reset-password', resetLimiter, async (req, res) => {
  const parsed = resetPasswordSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  const tokenHash = crypto.createHash('sha256').update(parsed.data.token).digest('hex');

  try {
    const tokenResult = await db.query(
      `SELECT id, user_id, expires_at, used_at
       FROM password_reset_tokens
       WHERE token_hash = $1`,
      [tokenHash]
    );

    if (tokenResult.rowCount === 0) {
      return res.status(400).json({ error: 'Invalid reset token' });
    }

    const tokenRow = tokenResult.rows[0];
    if (tokenRow.used_at) {
      return res.status(400).json({ error: 'Reset token already used' });
    }
    if (new Date(tokenRow.expires_at) <= new Date()) {
      return res.status(400).json({ error: 'Reset token expired' });
    }

    const passwordHash = await bcrypt.hash(parsed.data.newPassword, 12);
    await db.query(
      `UPDATE users
       SET password_hash = $1, auth_provider = 'email'
       WHERE id = $2`,
      [passwordHash, tokenRow.user_id]
    );

    await db.query('UPDATE password_reset_tokens SET used_at = NOW() WHERE id = $1', [tokenRow.id]);
    await db.query(
      'UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL',
      [tokenRow.user_id]
    );

    return res.json({ ok: true, message: 'Password reset successful. Please log in again.' });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to reset password' });
  }
});

module.exports = router;
