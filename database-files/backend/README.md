# Bondhu Backend API

This service provides a beginner-friendly auth and profile API over your PostgreSQL schema.

## Included Auth Features

- Email signup/login
- Google login with ID token
- JWT access token
- Refresh token rotation with revocation
- Logout endpoint
- Forgot-password endpoint with email reset link
- Reset-password endpoint using one-time token
- Simple in-memory rate limiting on auth endpoints
- Protected profile endpoints (`GET /profile/me`, `PATCH /profile/me`)

## API Endpoints

- `GET /health`
- `GET /live`
- `GET /ready`
- `GET /reset-password` (built-in reset password web page)
- `POST /auth/signup`
- `POST /auth/login`
- `POST /auth/google`
- `POST /auth/refresh`
- `POST /auth/logout`
- `POST /auth/forgot-password`
- `POST /auth/reset-password`
- `GET /profile/me` (Bearer token required)
- `PATCH /profile/me` (Bearer token required)
