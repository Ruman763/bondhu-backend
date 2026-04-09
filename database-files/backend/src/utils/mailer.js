const nodemailer = require('nodemailer');

function getTransporter() {
  const host = process.env.SMTP_HOST;
  const port = Number(process.env.SMTP_PORT || 587);
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;
  const from = process.env.SMTP_FROM;

  if (!host || !user || !pass || !from) {
    return null;
  }

  const transporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: {
      user,
      pass,
    },
  });

  return { transporter, from };
}

async function sendPasswordResetEmail(toEmail, resetLink) {
  const mail = getTransporter();
  if (!mail) {
    // Fallback for development-only setups.
    // eslint-disable-next-line no-console
    console.log(`[DEV PASSWORD RESET LINK] ${toEmail}: ${resetLink}`);
    return;
  }

  await mail.transporter.sendMail({
    from: mail.from,
    to: toEmail,
    subject: 'Reset your Bondhu password',
    text: `You requested a password reset. Open this link: ${resetLink}\n\nIf you did not request this, ignore this email.`,
    html: `<p>You requested a password reset.</p><p><a href="${resetLink}">Reset password</a></p><p>If you did not request this, ignore this email.</p>`,
  });
}

module.exports = {
  sendPasswordResetEmail,
};
