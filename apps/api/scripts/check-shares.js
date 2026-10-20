// Quick check: exact shares with creator included + discount, then cleanup.
const { PrismaClient } = require('@prisma/client');
const p = new PrismaClient();
const BASE = 'http://localhost:3000';
const post = (path, body, token) =>
  fetch(BASE + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
(async () => {
  const r1 = await post('/auth/login', { email: 'rich@minipay.test', password: 'Passw0rd!23' });
  const t = (await r1.json()).accessToken;
  const users = await (await fetch(BASE + '/admin/users', { headers: { Authorization: `Bearer ${t}` } })).json();
  const f = users.find((u) => u.email === 'friend@minipay.test');
  const res = await post('/split', {
    title: 'Share Check',
    participantUserIds: [f.id],
    items: [
      { name: 'Main', priceMinor: 3000 },
      { name: 'Dessert', priceMinor: 1000, assignedUserIds: [f.id] },
    ],
    extraMinor: 300,
    discountMinor: 200,
  }, t);
  console.log('create status:', res.status);
  const d = await res.json();
  const c = d.participants.find((x) => x.isCreator);
  const fr = d.participants.find((x) => x.userId === f.id);
  console.log('creator share:', c.shareAmount, '| friend share:', fr.shareAmount, '| total:', d.totalMinor);
  // main 3000/2 = 1500 each; dessert 1000 friend; adj +100 -> 50 each
  console.log('expected: creator 1550, friend 2550');
  const del = await fetch(BASE + '/split/' + d.id, { method: 'DELETE', headers: { Authorization: `Bearer ${t}` } });
  console.log('cleanup delete (unsent):', del.status);
  await p.$disconnect();
})().catch((e) => { console.error(e); process.exit(1); });
