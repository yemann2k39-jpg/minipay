// Deliver pending-deposit webhooks manually (no stripe CLI in this env).
// Run: node flush-deposits.js
const fs = require('node:fs');
const crypto = require('node:crypto');
const { execSync } = require('node:child_process');

const env = fs.readFileSync('.env', 'utf8');
const secret = env.match(/^STRIPE_WEBHOOK_SECRET=(.+)$/m)[1].trim().replace(/^["']|["']$/g, '');

const q = 'SELECT "stripePaymentIntentId" FROM "Transaction" WHERE type=\'DEPOSIT\' AND status=\'PENDING\' AND "stripePaymentIntentId" IS NOT NULL;';
const out = execSync(
  `docker exec -i minipay-db psql -U minipay -d minipay -At -c "${q.replace(/"/g, '\\"')}"`,
  { encoding: 'utf8' },
).trim();

const pis = out ? out.split('\n') : [];
if (!pis.length) { console.log('no pending deposits'); process.exit(0); }

(async () => {
  for (const pi of pis) {
    const payload = JSON.stringify({
      id: 'evt_flush_' + pi.slice(-8), object: 'event', type: 'payment_intent.succeeded',
      data: { object: { id: pi, object: 'payment_intent' } },
    });
    const t = Math.floor(Date.now() / 1000);
    const v1 = crypto.createHmac('sha256', secret).update(`${t}.${payload}`).digest('hex');
    const r = await fetch('http://localhost:3000/payments/webhook', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'stripe-signature': `t=${t},v1=${v1}` },
      body: payload,
    });
    console.log(pi, r.status, await r.text());
  }
})();
