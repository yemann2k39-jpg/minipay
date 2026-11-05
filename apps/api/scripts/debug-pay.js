// Debug: create a checkout with a fresh rotated key, pay it, print everything.
const BASE = 'http://localhost:3000';
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
  const usersRes = await get('/admin/users', t);
  const friend = usersRes.d.find((u) => u.email === 'friend@minipay.test');
  const merchants = (await get('/admin/merchants', t)).d;
  const shop = merchants.find((m) => m.name === 'PC Shop');
  const rk = await post(`/admin/merchants/${shop.id}/rotate-key`, null, t);
  const key = rk.d.apiKey;
  console.log('key rotated:', !!key);

  const created = await post('/merchant-api/checkout', {
    orderRef: 'PAYDBG-' + Date.now(),
    amountMinor: 5000,
    description: 'debug payment',
    callbackUrl: 'http://localhost:3999/cb',
  }, null, { 'X-API-Key': key });
  console.log('create:', created.s);
  if (created.s !== 201) { console.log(JSON.stringify(created.d)); return; }
  const checkoutId = created.d.checkoutId;

  const pay = await post(`/checkout/${checkoutId}/pay`, { pin: '123456' }, t);
  console.log('pay:', pay.s, JSON.stringify(pay.d).slice(0, 300));
})().catch((e) => console.error(e));
