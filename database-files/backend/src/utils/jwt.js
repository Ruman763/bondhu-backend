const jwt = require('jsonwebtoken');
const crypto = require('crypto');

const accessSecret = process.env.JWT_ACCESS_SECRET;
const refreshSecret = process.env.JWT_REFRESH_SECRET;
const accessExpiresIn = process.env.ACCESS_TOKEN_EXPIRES_IN || '15m';
const refreshDays = Number(process.env.REFRESH_TOKEN_EXPIRES_IN_DAYS || 30);

if (!accessSecret || !refreshSecret) {
  throw new Error('JWT_ACCESS_SECRET and JWT_REFRESH_SECRET are required');
}

function signAccessToken(user) {
  return jwt.sign(
    {
      sub: user.id,
      email: user.email,
    },
    accessSecret,
    { expiresIn: accessExpiresIn }
  );
}

function signRefreshToken(user) {
  const token = jwt.sign(
    {
      sub: user.id,
      email: user.email,
      type: 'refresh',
    },
    refreshSecret,
    { expiresIn: `${refreshDays}d` }
  );
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
  return { token, tokenHash, refreshDays };
}

function verifyAccessToken(token) {
  return jwt.verify(token, accessSecret);
}

function verifyRefreshToken(token) {
  return jwt.verify(token, refreshSecret);
}

module.exports = {
  signAccessToken,
  signRefreshToken,
  verifyAccessToken,
  verifyRefreshToken,
};
