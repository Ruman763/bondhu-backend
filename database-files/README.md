# Database Files (Single Folder)

This folder contains database-related files in one place:

- `docker-compose.yml` (Postgres + NocoDB + API)
- `.env.example`
- `init/001_bondhu_schema.sql`
- `backend/` (all backend API files)

## Quick start

```bash
cd "database-files"
cp .env.example .env
docker compose up -d
```

NocoDB UI:
- `http://YOUR_SERVER_IP:8080`

API health:
- `http://YOUR_SERVER_IP:3000/health`
