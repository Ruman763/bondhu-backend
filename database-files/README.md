# Database + Backend (One Place)

This folder contains a full self-hosted stack in one place:

- `docker-compose.yml` (Postgres + NocoDB + Node API + Socket.IO)
- `.env.example`
- `init/001_bondhu_schema.sql`
- `init/002_global_chat.sql`
- `backend/` (auth, profile, posts, realtime, admin panel)

## Quick start

```bash
cd "database-files"
cp .env.example .env
docker compose up -d --build
```

## One-link app setup

- API base URL: `https://backend.your-domain.com`
- Socket.IO URL: same host (`https://backend.your-domain.com/socket.io`)
- Admin panel: `https://backend.your-domain.com/admin`
- API health: `https://backend.your-domain.com/health`

## Admin panel

Set `ADMIN_PANEL_KEY` in `.env` (and deployment env) before use.

At `GET /admin` you can:
- view counts (users, posts, chats, messages)
- search users
- revoke user sessions (deletes refresh tokens)
