const { z } = require('zod');

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('production'),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().min(1),
  JWT_ACCESS_SECRET: z.string().min(32),
  JWT_REFRESH_SECRET: z.string().min(32),
  ACCESS_TOKEN_EXPIRES_IN: z.string().default('15m'),
  REFRESH_TOKEN_EXPIRES_IN_DAYS: z.coerce.number().int().positive().default(30),
  GOOGLE_CLIENT_ID: z.string().optional(),
  CORS_ORIGIN: z.string().default('*'),
  TRUST_PROXY: z.string().default('false'),
  APP_BASE_URL: z.string().default('http://localhost:3000'),
  PASSWORD_RESET_URL_BASE: z.string().default('http://localhost:3000/reset-password'),
  SMTP_HOST: z.string().optional(),
  SMTP_PORT: z.string().optional(),
  SMTP_USER: z.string().optional(),
  SMTP_PASS: z.string().optional(),
  SMTP_FROM: z.string().optional(),
});

const parsed = envSchema.safeParse(process.env);
if (!parsed.success) {
  // eslint-disable-next-line no-console
  console.error('Invalid environment configuration', parsed.error.flatten().fieldErrors);
  process.exit(1);
}

function parseTrustProxy(value) {
  const normalized = String(value).trim().toLowerCase();
  if (normalized === 'true') return true;
  if (normalized === 'false') return false;
  const maybeNumber = Number(normalized);
  if (Number.isInteger(maybeNumber) && maybeNumber >= 0) return maybeNumber;
  return false;
}

const env = {
  ...parsed.data,
  TRUST_PROXY: parseTrustProxy(parsed.data.TRUST_PROXY),
};

module.exports = {
  env,
};
