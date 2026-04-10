const express = require('express');
const path = require('path');
const db = require('../db');
const { env } = require('../config/env');

const router = express.Router();

function requireAdminKey(req, res, next) {
  const configuredKey = (env.ADMIN_PANEL_KEY || '').trim();
  if (!configuredKey) {
    return res.status(503).json({ error: 'Admin panel key is not configured' });
  }
  const providedKey = String(req.header('x-admin-key') || '').trim();
  if (!providedKey || providedKey !== configuredKey) {
    return res.status(401).json({ error: 'Unauthorized admin request' });
  }
  return next();
}

router.get('/', (req, res) => {
  const filePath = path.join(__dirname, '..', 'public', 'admin.html');
  return res.sendFile(filePath);
});

router.get('/api/overview', requireAdminKey, async (req, res) => {
  try {
    const [users, posts, chats, messages] = await Promise.all([
      db.query('SELECT COUNT(*)::int AS count FROM users'),
      db.query('SELECT COUNT(*)::int AS count FROM posts'),
      db.query('SELECT COUNT(*)::int AS count FROM chats'),
      db.query('SELECT COUNT(*)::int AS count FROM messages'),
    ]);

    return res.json({
      users: users.rows[0]?.count || 0,
      posts: posts.rows[0]?.count || 0,
      chats: chats.rows[0]?.count || 0,
      messages: messages.rows[0]?.count || 0,
    });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to load overview' });
  }
});

router.get('/api/users', requireAdminKey, async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit, 10) || 50, 100);
  const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);
  const search = String(req.query.search || '').trim().toLowerCase();
  try {
    const result = await db.query(
      `SELECT u.id, u.email, u.auth_provider, u.created_at, p.display_name, p.avatar_url
       FROM users u
       LEFT JOIN profiles p ON p.user_id = u.id
       WHERE ($1 = '' OR lower(u.email) LIKE ('%' || $1 || '%') OR lower(coalesce(p.display_name, '')) LIKE ('%' || $1 || '%'))
       ORDER BY u.created_at DESC
       LIMIT $2 OFFSET $3`,
      [search, limit, offset]
    );
    return res.json({ users: result.rows });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to load users' });
  }
});

router.post('/api/users/:id/revoke-sessions', requireAdminKey, async (req, res) => {
  const userId = String(req.params.id || '').trim();
  if (!userId) return res.status(400).json({ error: 'User id is required' });
  try {
    await db.query('DELETE FROM refresh_tokens WHERE user_id = $1', [userId]);
    return res.json({ ok: true });
  } catch (error) {
    return res.status(500).json({ error: 'Failed to revoke sessions' });
  }
});

module.exports = router;
