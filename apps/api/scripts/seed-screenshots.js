/* Screenshot demo data seeder — Neko Cafe + Alex + Sara (and friends).
   All money movements go through the real API so the ledger stays balanced.
   Run: node seed-screenshots.js  (from apps/api) */
const BASE = 'http://localhost:3000';
const PASS = 'password12';
const PIN = '123456';

const j = async (method, path, token, body) => {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = text; }
  if (!res.ok) {
    throw new Error(`${method} ${path} -> ${res.status}: ${text.slice(0, 300)}`);
  }
  return data;
};

const login = (email) => j('POST', '/auth/login', null, { email, password: PASS });

async function register(email, displayName) {
  try {
    const r = await j('POST', '/auth/register', null, { email, password: PASS, displayName });
    console.log(`registered ${email}`);
    return r;
  } catch (e) {
    if (String(e).includes('409')) {
      console.log(`${email} already exists, logging in`);
      return login(email);
    }
    throw e;
  }
}

async function deposit(token, amount) {
  const dep = await j('POST', '/wallet/deposits', token, { amount });
  const id = dep.id || dep.transactionId || dep.depositId;
  await j('POST', `/wallet/deposits/${id}/confirm-test`, token, { card: 'visa' });
  // No stripe CLI here: simulate the signed webhook (the single credit writer).
  await deliverWebhook(dep.paymentIntentId);
  console.log(`deposit ${amount / 100} SGD ok`);
}

/** Build + sign a payment_intent.succeeded event exactly like Stripe does. */
async function deliverWebhook(piId) {
  const fs = require('node:fs');
  const crypto = require('node:crypto');
  const env = fs.readFileSync('.env', 'utf8');
  const secret = env.match(/^STRIPE_WEBHOOK_SECRET=(.+)$/m)?.[1]?.trim().replace(/^"|"$/g, '');
  if (!secret) throw new Error('STRIPE_WEBHOOK_SECRET not found in .env');
  const payload = JSON.stringify({
    id: `evt_seed_${piId.slice(0, 12)}`,
    object: 'event',
    type: 'payment_intent.succeeded',
    data: { object: { id: piId, object: 'payment_intent' } },
  });
  const t = Math.floor(Date.now() / 1000);
  const v1 = crypto.createHmac('sha256', secret).update(`${t}.${payload}`).digest('hex');
  const res = await fetch(`${BASE}/payments/webhook`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'stripe-signature': `t=${t},v1=${v1}` },
    body: payload,
  });
  if (!res.ok) throw new Error(`webhook -> ${res.status}: ${await res.text()}`);
  await res.json(); // { received: true }
}

async function main() {
  // 1. Accounts
  const alex = await register('alex@minipay.test', 'Alex Tan');
  const sara = await register('sara@minipay.test', 'Sara Lim');
  const neko = await j('POST', '/auth/register-business', null, {
    email: 'nekocafe@minipay.test', password: PASS,
    displayName: 'Mei Wong', businessName: 'Neko Cafe',
  }).catch(async (e) => {
    if (String(e).includes('409')) { console.log('nekocafe exists, logging in'); return login('nekocafe@minipay.test'); }
    throw e;
  });
  console.log(`Neko Cafe merchant code: ${neko.merchant?.code ?? '(existing)'}`);

  const alexT = alex.accessToken, saraT = sara.accessToken, nekoT = neko.accessToken;

  // 2. Payment PINs (409 = already set)
  for (const [name, t] of [['alex', alexT], ['sara', saraT], ['neko', nekoT]]) {
    try { await j('POST', '/auth/pin', t, { pin: PIN }); console.log(`${name} PIN set`); }
    catch (e) { if (!String(e).includes('409')) throw e; console.log(`${name} PIN already set`); }
  }

  // 3. Deposits (top-ups)
  await deposit(alexT, 20000);
  await deposit(alexT, 15000);
  await deposit(saraT, 12000);

  // 4. Contacts — Alex gets everyone, Sara the main ones
  for (const [t, query, alias] of [
    [alexT, 'sara@minipay.test', 'Sara'],
    [alexT, 'rich@minipay.test', 'Rich'],
    [alexT, 'friend@minipay.test', 'Good Friend'],
    [alexT, 'nekocafe@minipay.test', 'Neko Cafe'],
    [alexT, 'merchant@minipay.test', 'Kopi Corner'],
    [saraT, 'alex@minipay.test', 'Alex'],
    [saraT, 'rich@minipay.test', 'Rich'],
    [saraT, 'friend@minipay.test', 'Good Friend'],
    [nekoT, 'alex@minipay.test', 'Alex Tan'],
    [nekoT, 'sara@minipay.test', 'Sara Lim'],
    [nekoT, 'rich@minipay.test', 'Rich Tan'],
  ]) {
    try { await j('POST', '/contacts', t, { query, alias }); } catch (e) {
      if (!String(e).includes('Already in your contacts') && !String(e).includes('409')) throw e;
    }
  }
  console.log('contacts added');

  // 5. P2P transfers (minor units) — last one will be backdated to last month
  const transfers = [
    [alexT, 'sara@minipay.test', 1250],
    [saraT, 'alex@minipay.test', 820],
    [alexT, 'sara@minipay.test', 2500],
    [alexT, 'friend@minipay.test', 675],
    [saraT, 'alex@minipay.test', 1500],
    [alexT, 'sara@minipay.test', 990],
  ];
  for (const [t, to, amount] of transfers) {
    const user = await j('GET', '/contacts/lookup?query=' + to, t);
    await j('POST', '/wallet/transfer', t, { toUserId: user.userId, amount, pin: PIN });
    console.log(`transfer ${amount / 100} SGD -> ${user.displayName}`);
  }

  // 6. Neko Cafe sales across the last 7 days + a couple for last month
  const payers = [alexT, saraT, alexT, saraT, alexT, saraT, alexT, saraT, alexT, saraT];
  const amounts = [450, 1200, 680, 950, 540, 880, 1100, 720, 650, 980];
  const saleIds = [];
  for (let i = 0; i < amounts.length; i++) {
    const s = await j('POST', '/merchants/mine/collect', nekoT, {
      amountMinor: amounts[i],
      description: ['Latte', 'Catpuccino', 'Mocha', 'Croissant', 'Espresso', 'Cheesecake', 'Green tea latte', 'Tiramisu', 'Flat white', 'Brunch set'][i],
    });
    const id = s.id || s.sessionId || s.checkoutId;
    saleIds.push(id);
    const payerToken = payers[i];
    await j('POST', `/checkout/${id}/pay`, payerToken, { pin: PIN });
    console.log(`sale ${(amounts[i] / 100).toFixed(2)} SGD paid (checkout ${id.slice(0, 8)})`);
  }

  // 7. Refund one recent sale
  const sales = await j('GET', '/merchants/mine/sales?take=20', nekoT);
  const list = sales.items || sales;
  const paid = list.find((x) => x.status === 'PAID');
  if (paid) {
    await j('POST', `/merchants/mine/sales/${paid.id}/refund`, nekoT, {});
    console.log(`refunded sale ${paid.id.slice(0, 8)}`);
  }

  // 8. Withdraw payout to owner wallet
  await j('POST', '/merchants/mine/withdraw', nekoT, { amountMinor: 15000 });
  console.log('withdraw 150 SGD to owner wallet');

  // 9. Extra login each account (so the security screen shows 2+ sessions)
  await login('alex@minipay.test');
  await login('sara@minipay.test');
  await login('nekocafe@minipay.test');

  // 10. Money request for the requests screen (Sara requests from Alex)
  // (uses the real flow: POST /requests)
  try {
    await j('POST', '/requests', alexT, { toEmail: 'sara@minipay.test', amountMinor: 1850, note: 'Concert tickets' });
    console.log('money request created');
  } catch (e) { console.log(`request skipped: ${String(e).slice(0, 120)}`); }

  console.log('SEED COMPLETE');
  console.log(JSON.stringify({
    alexToken: alexT, saraToken: saraT, nekoToken: nekoT,
    saleIds,
  }, null, 0));
}

main().catch((e) => { console.error('FAILED:', e.message || e); process.exit(1); });
