require('dotenv').config();
const http = require('http');
const express = require('express');
const path = require('path');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const { Server } = require('socket.io');

const authRoutes = require('./routes/auth');
const profileRoutes = require('./routes/profile');
const postsRoutes = require('./routes/posts');
const adminRoutes = require('./routes/admin');
const db = require('./db');
const { env } = require('./config/env');
const { attachBondhuSocket } = require('./socket/bondhuSocket');

const app = express();
const port = env.PORT;
const corsOrigin = env.CORS_ORIGIN;

app.disable('x-powered-by');
app.set('trust proxy', env.TRUST_PROXY);

app.use(
  helmet({
    contentSecurityPolicy: false,
    crossOriginResourcePolicy: { policy: 'cross-origin' },
  })
);
app.use(cors({ origin: corsOrigin === '*' ? true : corsOrigin.split(',').map((s) => s.trim()) }));
app.use(express.json({ limit: '2mb' }));
app.use(morgan('tiny'));

app.get('/', (req, res) => {
  return res.json({
    ok: true,
    service: 'bondhu-api',
    endpoints: {
      health: '/health',
      ready: '/ready',
      live: '/live',
      auth: '/auth',
      profile: '/profile',
      posts: '/posts',
      socket: '/socket.io',
      admin: '/admin',
      resetPasswordPage: '/reset-password',
    },
  });
});

app.get('/live', (req, res) => {
  return res.json({ ok: true, service: 'bondhu-api' });
});

app.get('/ready', async (req, res) => {
  try {
    await db.query('SELECT 1');
    return res.json({ ok: true, service: 'bondhu-api' });
  } catch (error) {
    return res.status(500).json({ ok: false, error: 'Database unavailable' });
  }
});

app.get('/health', async (req, res) => {
  try {
    await db.query('SELECT 1');
    return res.json({ ok: true, service: 'bondhu-api' });
  } catch (error) {
    return res.status(500).json({ ok: false, error: 'Database unavailable' });
  }
});

app.get('/reset-password', (req, res) => {
  const filePath = path.join(__dirname, 'public', 'reset-password.html');
  return res.sendFile(filePath);
});

app.use('/auth', authRoutes);
app.use('/profile', profileRoutes);
app.use('/posts', postsRoutes);
app.use('/admin', adminRoutes);

app.use((req, res) => {
  return res.status(404).json({ error: 'Route not found' });
});

app.use((error, req, res, next) => {
  // eslint-disable-next-line no-console
  console.error('Unhandled API error', error);
  return res.status(500).json({ error: 'Internal server error' });
});

const server = http.createServer(app);

const io = new Server(server, {
  cors: {
    origin: corsOrigin === '*' ? true : corsOrigin.split(',').map((s) => s.trim()),
    methods: ['GET', 'POST'],
  },
  transports: ['websocket', 'polling'],
});

attachBondhuSocket(io);

server.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`Bondhu API + Socket.IO listening on :${port}`);
});

async function shutdown(signal) {
  // eslint-disable-next-line no-console
  console.log(`Received ${signal}, shutting down gracefully...`);
  io.close(() => {
    server.close(async () => {
      await db.pool.end();
      process.exit(0);
    });
  });
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
