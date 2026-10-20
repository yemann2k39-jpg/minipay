// Clean up smoke-test split data, then verify the fixed link + pay flow.
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
const login = async (email) => {
  const r = await post('/auth/login', { email, password: 'Passw0rd!23' });
  return (await r.json()).accessToken;
};

(async () => {
  // 1. Remove the earlier broken smoke session + its request
  const bad = await p.splitSession.findMany({ where: { title: 'Smoke Dinner' } });
  for (const s of bad) {
    await p.moneyRequest.deleteMany({ where: { splitSessionId: s.id } });
    await p.splitSession.delete({ where: { id: s.id } });
  }
  console.log('cleaned broken sessions:', bad.length);

  const rich = await login('rich@minipay.test');
  const friend = await login('friend@minipay.test');

  // 2. Create a fresh split (2 participants: friend + demoncool if exists, else just friend)
  const users = await (await get('/admin/users', rich)).json();
  const friendId = users.find((u) => u.email === 'friend@minipay.test').id;
  const other = users.find((u) => u.email === 'demoncool675@gmail.com');
  const participants = other ? [friendId, other.id] : [friendId];

  // 3 items with a subset assignment + extra: pizza shared by all, salad only for friend
  const items = [
    { name: 'Pizza', priceMinor: 3000 },
    { name: 'Salad', priceMinor: 1000, assignedUserIds: [friendId] },
    { name: 'Coke', priceMinor: 200 },
  ];
  const extra = 300;
  const createRes = await post('/split', {
    title: 'Verify Dinner',
    participantUserIds: participants,
    items,
    extraMinor: extra,
  }, rich);
  const created = await createRes.json();
  console.log('create status:', createRes.status, '| all linked:', created.participants.every((x) => x.requestId));

  // 3. List — statuses must be live now
  const list = await (await get('/split', rich)).json();
  const sess = list.sessions[0];
  console.log('list first:', sess.title, '| pending:', sess.pendingMinor, '| total:', sess.totalMinor);
  sess.participants.forEach((x) => console.log('  ', x.displayName, 'owes', x.shareAmount, 'status', x.status));

  // Expected: total = 3000+1000+200+300 = 4500
  // friend: salad 1000 + (3000+200+300)/2 = 1000 + 1750 = 2750
  // other: 1750
  // Verify shares sum to total
  const sumShares = sess.participants.reduce((a, x) => a + Number(x.shareAmount), 0);
  console.log('sum of shares == total:', sumShares === Number(sess.totalMinor));

  // 4. Friend pays their request through the requests API
  const reqs = await (await get('/requests', friend)).json();
  const mine = reqs.toMe.find((r) => r.status === 'PENDING');
  if (mine) {
    const payRes = await post(`/requests/${mine.id}/pay`, { pin: '123456' }, friend);
    const paid = await payRes.json();
    console.log('friend paid:', payRes.status, paid.status);
  } else {
    console.log('friend has no pending request (unexpected)');
  }

  // 5. Split now reflects PAID for friend
  const after = await (await get(`/split/${sess.id}`, rich)).json();
  after.participants.forEach((x) => console.log('  after:', x.displayName, 'status', x.status));
  console.log('paidMinor:', after.paidMinor, 'pendingMinor:', after.pendingMinor);

  // 6. Ledger invariant
  const inv = await (await get('/ledger/invariant', rich)).json();
  console.log('ledger invariant ok:', inv.ok);

  await p.$disconnect();
})().catch((e) => { console.error(e); process.exit(1); });
