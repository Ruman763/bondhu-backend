/**
 * Socket.IO — same events as the legacy Bondhu chat server (Render).
 * Persists global + private messages to PostgreSQL when users exist in DB.
 */
const db = require('../db');

const GLOBAL_CHAT_ID = '00000000-0000-0000-0000-000000000001';

function normEmail(s) {
  return (s || '').toString().trim().toLowerCase();
}

async function userIdByEmail(email) {
  const e = normEmail(email);
  if (!e || !e.includes('@')) return null;
  const r = await db.query('SELECT id FROM users WHERE lower(email) = lower($1) LIMIT 1', [e]);
  return r.rows[0]?.id ?? null;
}

async function getOrCreatePrivateChatId(userId1, userId2) {
  const r = await db.query(
    `SELECT c.id::text AS id FROM chats c
     INNER JOIN chat_members m1 ON m1.chat_id = c.id AND m1.user_id = $1
     INNER JOIN chat_members m2 ON m2.chat_id = c.id AND m2.user_id = $2
     WHERE c.type = 'private' LIMIT 1`,
    [userId1, userId2]
  );
  if (r.rows[0]) return r.rows[0].id;
  const ins = await db.query(
    `INSERT INTO chats (type, created_by) VALUES ('private', $1) RETURNING id`,
    [userId1]
  );
  const cid = ins.rows[0].id;
  await db.query(
    `INSERT INTO chat_members (chat_id, user_id) VALUES ($1::uuid, $2::uuid), ($1::uuid, $3::uuid)`,
    [cid, userId1, userId2]
  );
  return cid;
}

async function persistMessage({ chatId, senderId, messageType, content, metadata }) {
  try {
    await db.query(
      `INSERT INTO messages (chat_id, sender_id, message_type, content, metadata)
       VALUES ($1::uuid, $2::uuid, $3, $4, $5::jsonb)`,
      [chatId, senderId, messageType, content || '', JSON.stringify(metadata || {})]
    );
  } catch (e) {
    // eslint-disable-next-line no-console
    console.warn('[socket] persistMessage failed', e.message);
  }
}

function attachBondhuSocket(io) {
  io.on('connection', (socket) => {
    socket.on('join_room', (room) => {
      const r = normEmail(room?.toString?.() ?? room);
      if (!r) return;
      socket.join(r);
    });

    socket.on('user_online', (data) => {
      socket.broadcast.emit('user_online', data);
    });

    socket.on('register_fcm', async (data) => {
      try {
        const email = normEmail(data?.email);
        const token = data?.token?.toString();
        if (!email || !token) return;
        const uid = await userIdByEmail(email);
        if (uid) {
          await db.query('UPDATE profiles SET fcm_token = $1 WHERE user_id = $2', [token, uid]);
        }
      } catch (_) {}
    });

    socket.on('message', async (data) => {
      const payload = data && typeof data === 'object' ? { ...data } : {};
      io.to('group_global').emit('message', payload);
      try {
        const senderEmail = normEmail(payload.senderId || payload.authorEmail);
        const uid = await userIdByEmail(senderEmail);
        if (uid) {
          await persistMessage({
            chatId: GLOBAL_CHAT_ID,
            senderId: uid,
            messageType: (payload.type || 'text').toString(),
            content: (payload.text || '').toString(),
            metadata: {
              author: payload.author,
              authorEmail: payload.authorEmail,
              id: payload.id,
            },
          });
        }
      } catch (_) {}
    });

    socket.on('private_message', async (data) => {
      const payload = data && typeof data === 'object' ? { ...data } : {};
      const target = normEmail(payload.targetId);
      const sender = normEmail(payload.senderId);
      if (target) io.to(target).emit('private_message', payload);
      if (sender && sender !== target) io.to(sender).emit('private_message', payload);

      try {
        const sUid = await userIdByEmail(sender);
        const tUid = await userIdByEmail(target);
        if (sUid && tUid) {
          const chatId = await getOrCreatePrivateChatId(sUid, tUid);
          await persistMessage({
            chatId,
            senderId: sUid,
            messageType: (payload.type || 'text').toString(),
            content: (payload.text || '').toString(),
            metadata: {
              replyToId: payload.replyToId,
              replyToText: payload.replyToText,
              noRush: payload.noRush,
              clientMsgId: payload.id,
            },
          });
        }
      } catch (_) {}
    });

    socket.on('typing', (data) => {
      const t = normEmail(data?.target || data?.chatId);
      if (t) io.to(t).emit('typing', data);
    });

    socket.on('message_reaction', (data) => {
      const t = normEmail(data?.target || data?.chatId);
      if (t) io.to(t).emit('message_reaction', data);
    });

    socket.on('edit_message', (data) => {
      const t = normEmail(data?.target || data?.chatId);
      if (t) io.to(t).emit('edit_message', data);
    });

    socket.on('read_receipt', (data) => {
      const t = normEmail(data?.target || data?.senderId);
      if (t) io.to(t).emit('read_receipt', data);
    });

    socket.on('mark_read', (data) => {
      const senderEmail = normEmail(data?.target);
      const reader = normEmail(data?.readerId);
      const ids = Array.isArray(data?.messageIds) ? data.messageIds : [];
      if (!senderEmail || !reader || ids.length === 0) return;
      const readAt = new Date().toISOString();
      ids.forEach((mid) => {
        io.to(senderEmail).emit('read_receipt', {
          target: reader,
          msgId: mid?.toString?.() ?? String(mid),
          readAt,
        });
      });
    });

    const relayTo = (event, getTargetId) => {
      socket.on(event, (payload) => {
        const id = normEmail(getTargetId(payload));
        if (id) io.to(id).emit(event, payload);
      });
    };

    socket.on('call_user', (payload) => {
      const to = normEmail(payload?.to);
      if (to) io.to(to).emit('incoming_call', payload);
    });

    relayTo('call_candidate', (p) => p?.target);
    relayTo('call_accepted', (p) => p?.to);
    relayTo('end_call', (p) => p?.to);
    relayTo('call_declined', (p) => p?.to);
    relayTo('call_not_answered_message', (p) => p?.to);
    relayTo('call_history', (p) => p?.to);
    relayTo('live_script_data', (p) => p?.target);
  });
}

module.exports = { attachBondhuSocket };
