const express = require('express');
const { z } = require('zod');
const db = require('../db');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

const updateProfileSchema = z.object({
  displayName: z.string().min(1).max(120).optional(),
  avatarUrl: z.string().url().optional().nullable(),
  bio: z.string().max(1000).optional().nullable(),
  location: z.string().max(200).optional().nullable(),
  languageCode: z.string().max(10).optional(),
  darkMode: z.boolean().optional(),
});

router.get('/me', requireAuth, async (req, res) => {
  try {
    const result = await db.query(
      `SELECT u.id, u.email, p.display_name, p.avatar_url, p.bio, p.location,
              p.language_code, p.dark_mode, p.created_at, p.updated_at
       FROM users u
       LEFT JOIN profiles p ON p.user_id = u.id
       WHERE u.id = $1`,
      [req.auth.userId]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    return res.json({ user: result.rows[0] });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to fetch profile' });
  }
});

router.patch('/me', requireAuth, async (req, res) => {
  const parsed = updateProfileSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  const payload = parsed.data;
  const fields = [];
  const values = [];
  let idx = 1;

  if (payload.displayName !== undefined) {
    fields.push(`display_name = $${idx++}`);
    values.push(payload.displayName);
  }
  if (payload.avatarUrl !== undefined) {
    fields.push(`avatar_url = $${idx++}`);
    values.push(payload.avatarUrl);
  }
  if (payload.bio !== undefined) {
    fields.push(`bio = $${idx++}`);
    values.push(payload.bio);
  }
  if (payload.location !== undefined) {
    fields.push(`location = $${idx++}`);
    values.push(payload.location);
  }
  if (payload.languageCode !== undefined) {
    fields.push(`language_code = $${idx++}`);
    values.push(payload.languageCode);
  }
  if (payload.darkMode !== undefined) {
    fields.push(`dark_mode = $${idx++}`);
    values.push(payload.darkMode);
  }

  if (fields.length === 0) {
    return res.status(400).json({ error: 'No profile fields supplied' });
  }

  values.push(req.auth.userId);
  const query = `
    UPDATE profiles
    SET ${fields.join(', ')}
    WHERE user_id = $${idx}
    RETURNING user_id, display_name, avatar_url, bio, location, language_code, dark_mode, updated_at
  `;

  try {
    const result = await db.query(query, values);
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Profile not found' });
    }
    return res.json({ profile: result.rows[0] });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to update profile' });
  }
});

module.exports = router;
