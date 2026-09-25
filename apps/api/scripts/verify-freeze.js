// Verifies frozen-account enforcement end to end, then restores state.
const { PrismaClient } = require('@prisma/client');
const p = new PrismaClient();
const BASE = 'http://localhost:3000';

const post = (path, body, token) =>
  fetch(BASE + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
const get = (path, token) =>
  fetch(BASE + path, { headers: token ? { Authorization: `Bearer ${token}` } : {} });

(async () => {
  const login = async (email) => {
    const r = await post('/auth/login', { email, password: 'Passw0rd!23' });
    if (r.status !== 200 && r.status !== 201) throw new Error(`login ${email} -> ${r.status}`);
    return (await r.json()).accessToken;
  };
  const rich = await login('rich@minipay.test');
  const freeze = await post('/admin/users', null, rich); // wrong usage guard
  void freeze;
  const users = await (await get('/admin/users', rich)).json();
  const friend = users.find((u) => u.email === 'friend@minipay.test');

  // 1. Freeze friend as admin
  await post(`/admin/users/${friend.id}/freeze`, null, rich);

  // 2. Friend can still log in
  const friendLogin = await post('/auth/login', { email: 'friend@minipay.test', password: 'Passw0rd!23' });
  console.log('frozen login allowed:', friendLogin.status === 200 || friendLogin.status === 201);
  const friendToken = (await friendLogin.json()).accessToken;

  // 3. Frozen deposit blocked
  const dep = await post('/wallet/deposits', { amount: 1000 }, friendToken);
  const depBody = await dep.json();
  console.log('frozen deposit blocked:', dep.status === 403, '|', depBody.message);

  // 4. Frozen transfer OUT blocked
  const tr = await post('/wallet/transfer', { toEmail: 'rich@minipay.test', amount: 300, pin: '123456' }, friendToken);
  const trBody = await tr.json();
  console.log('frozen transfer-out blocked:', tr.status === 403, '|', trBody.message);

  // 5. Receiving money still allowed (rich -> frozen friend)
  const trIn = await post('/wallet/transfer', { toEmail: 'friend@minipay.test', amount: 200, pin: '123456' }, rich);
  console.log('transfer TO frozen allowed:', trIn.status === 200 || trIn.status === 201);

  // 6. Lookup finds frozen user
  const lookup = await get('/contacts/lookup?query=friend@minipay.test', rich);
  console.log('frozen user lookup allowed:', lookup.status === 200 || lookup.status === 201);

  // 7. Unfreeze (restore)
  await post(`/admin/users/${friend.id}/unfreeze`, null, rich);
  const after = await (await get('/admin/users', rich)).json();
  const f2 = after.find((u) => u.email === 'friend@minipay.test');
  console.log('restored to ACTIVE:', f2.status === 'ACTIVE');

  await p.$disconnect();
})().catch((e) => { console.error(e); process.exit(1); });
