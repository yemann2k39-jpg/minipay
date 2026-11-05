// Creates a demo checkout for the PC Shop and prints the hosted page URL.
const BASE = 'http://localhost:3000';
const fs = require('fs');
const j = async (r) => { try { return await r.json(); } catch { return null; } };
const post = async (path, body, token, headers = {}) => {
  const r = await fetch(BASE + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { s: r.status, d: await j(r) };
};
const get = async (path, token) => {
  const r = await fetch(BASE + path, { headers: { Authorization: `Bearer ${token}` } });
  return { s: r.status, d: await j(r) };
};
(async () => {
  const login = await post('/auth/login', { email: 'rich@minipay.test', password: 'Passw0rd!23' });
  const t = login.d.accessToken;
  const merchants = (await get('/admin/merchants', t)).d;
  const shop = merchants.find((m) => m.name === 'PC Shop');
  const rk = await post(`/admin/merchants/${shop.id}/rotate-key`, {}, t);
  const key = rk.d.apiKey;
  fs.writeFileSync('scripts/demo-api-key.txt', key);

  const created = await post('/merchant-api/checkout', {
    orderRef: 'ORDER-DEMO-1',
    amountMinor: 15900,
    description: 'GPU cable + case fan (demo)',
    callbackUrl: 'http://localhost:3999/cb',
  }, null, { 'X-API-Key': key });
  if (created.s !== 201) {
    console.log('create failed:', created.s, JSON.stringify(created.d));
    return;
  }
  fs.writeFileSync('scripts/demo-checkout-id.txt', created.d.checkoutId);
  console.log('DEMO CHECKOUT READY');
  console.log('checkoutUrl:', created.d.checkoutUrl);
  console.log('id:', created.d.checkoutId);
})().catch((e) => console.error(e));
