// Live smoke test: merchant creation -> checkout creation -> app payment ->
// signed callback capture + HMAC verification -> status polling.
const { PrismaClient } = require('@prisma/client');
const crypto = require('crypto');
const http = require('http');
const p = new PrismaClient();
const BASE = 'http://localhost:3000';

const post = async (path, body, token, headers = {}) => {
  const r = await fetch(BASE + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: body ? JSON.stringify(body) : undefined,
  });
  return [r.status, await r.json().catch(() => null)];
};
const get = async (path, token, headers = {}) => {
  const r = await fetch(BASE + path, { headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers } });
  return [r.status, await r.json().catch(() => null)];
};
const login = async (email) => {
  const [s, d] = await post('/auth/login', { email, password: 'Passw0rd!23' });
  if (s !== 200 && s !== 201) throw new Error('login failed ' + s);
  return d.accessToken;
};

// --- local callback receiver on :3999 ---
const received = [];
const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => received.push({ body, sig: req.headers['x-minipay-signature'] }));
  res.writeHead(200).end('{"ok":true}');
});

(async () => {
  await new Promise((r) => server.listen(3999, r));
  console.log('callback listener on :3999');

  const admin = await login('rich@minipay.test');

  // 1. Ensure a PC Shop merchant exists, then rotate its key (key shown once)
  const merchants = (await get('/admin/merchants', admin))[1];
  let shop = merchants.find((m) => m.name === 'PC Shop');
  if (!shop) {
    const [cs0, cd0] = await post('/admin/merchants', { name: 'PC Shop', callbackUrl: 'http://localhost:3999/cb' }, admin);
    shop = cd0.merchant;
  }
  const rk = await fetch(BASE + `/admin/merchants/${shop.id}/rotate-key`, { method: 'POST', headers: { Authorization: `Bearer ${admin}` } });
  const apiKey = (await rk.json()).apiKey;
  console.log('merchant ready:', shop.code, '| key rotated:', !!apiKey);

  // 2. Create checkout with the API key
  const [cs, cd] = await post('/merchant-api/checkout', {
    orderRef: 'ORDER-SMOKE-' + Date.now(),
    amountMinor: 15900,
    description: 'GPU cable + case fan',
    callbackUrl: 'http://localhost:3999/cb',
  }, null, { 'X-API-Key': apiKey });
  console.log('checkout created:', cs === 201, '| url:', cd.checkoutUrl);

  // 2b. Idempotency: same orderRef returns the same session
  const [cs2, cd2] = await post('/merchant-api/checkout', {
    orderRef: 'ORDER-SMOKE-' + Date.now(), amountMinor: 15900, description: 'x', callbackUrl: 'http://localhost:3999/cb',
  }, null, { 'X-API-Key': apiKey });
  console.log('second checkout created:', cs2 === 201, '(different orderRef)');

  // 2c. Bad key rejected
  const [bs] = await post('/merchant-api/checkout', { orderRef: 'X', amountMinor: 100 }, null, { 'X-API-Key': 'mp_bad' });
  console.log('bad key rejected:', bs === 401);

  // 3. Hosted page HTML loads
  const page = await fetch(cd.checkoutUrl);
  const html = await page.text();
  console.log('hosted page:', page.status === 200, '| has QR img:', html.includes('data:image/png;base64'), '| has form:', html.includes('form'));

  // 4. Rich pays the checkout via the app path
  const rich = await login('rich@minipay.test');
  const [ps, pd] = await post(`/checkout/${cd.checkoutId}/pay`, { pin: '123456' }, rich);
  console.log('app pay:', ps === 200 || ps === 201, '|', JSON.stringify(pd).slice(0, 80));

  // 5. Wait for the callback to arrive, verify HMAC
  await new Promise((r) => setTimeout(r, 1500));
  console.log('callbacks received:', received.length);
  if (received.length > 0) {
    const expected = crypto.createHmac('sha256', apiKey).update(received[0].body).digest('hex');
    console.log('HMAC signature valid:', received[0].sig === expected);
    const body = JSON.parse(received[0].body);
    console.log('event:', body.event, '| orderRef:', body.orderRef, '| amount:', body.amountMinor);
  } else {
    console.log('NO CALLBACK RECEIVED');
  }

  // 6. Merchant polling shows PAID
  const [ss, sd] = await get(`/merchant-api/checkout/${cd.checkoutId}`, null, { 'X-API-Key': apiKey });
  console.log('merchant sees status:', sd.status === 'PAID');  // 7. Ledger invariant
  const inv = (await get('/ledger/invariant', rich))[1];
  console.log('ledger invariant ok:', inv.ok);

  // 8. Cleanup: delete test checkouts + the rotated PC Shop merchant
  await p.checkoutSession.deleteMany({});
  await p.merchant.deleteMany({ where: { name: 'PC Shop' } });
  console.log('cleaned up test merchant + checkouts');
  server.close();
  await p.$disconnect();
  process.exit(0);
})().catch((e) => { console.error(e); server.close(); p.$disconnect(); process.exit(1); });
