const express = require('express');
const { z } = require('zod');
const db = require('../db');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

const createPostSchema = z.object({
  content: z.string().max(8000).optional().default(''),
  mediaUrl: z.string().url().optional().nullable(),
  postType: z.string().max(32).optional().default('post'),
});

router.get('/', requireAuth, async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit, 10) || 50, 100);
  const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);
  try {
    const result = await db.query(
      `SELECT p.id, p.user_id, p.content, p.media_url, p.post_type, p.created_at,
              u.email AS author_email,
              pr.display_name, pr.avatar_url
       FROM posts p
       JOIN users u ON u.id = p.user_id
       LEFT JOIN profiles pr ON pr.user_id = p.user_id
       ORDER BY p.created_at DESC
       LIMIT $1 OFFSET $2`,
      [limit, offset]
    );
    const rows = result.rows.map((row) => ({
      id: row.id,
      author_id: row.user_id,
      user_id: row.user_id,
      content: row.content,
      media_url: row.media_url,
      type: row.post_type,
      created_at: row.created_at,
      author_email: row.author_email,
      display_name: row.display_name,
      avatar_url: row.avatar_url,
      likes: [],
      saved_by: [],
      comments: [],
    }));
    return res.json({ posts: rows });
  } catch (e) {
    return res.status(500).json({ error: 'Failed to list posts' });
  }
});

router.post('/', requireAuth, async (req, res) => {
  const parsed = createPostSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }
  const { content, mediaUrl, postType } = parsed.data;
  try {
    const ins = await db.query(
      `INSERT INTO posts (user_id, content, media_url, post_type)
       VALUES ($1, $2, $3, $4)
       RETURNING id, user_id, content, media_url, post_type, created_at`,
      [req.auth.userId, content || '', mediaUrl || null, postType]
    );
    const row = ins.rows[0];
    return res.status(201).json({
      post: {
        id: row.id,
        author_id: row.user_id,
        content: row.content,
        media_url: row.media_url,
        type: row.post_type,
        created_at: row.created_at,
        likes: [],
        saved_by: [],
        comments: [],
      },
    });
  } catch (e) {
    return res.status(500).json({ error: 'Failed to create post' });
  }
});

module.exports = router;
