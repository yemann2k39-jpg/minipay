// Verifies the updated split flow:
// creator included as shareholder, no auto-requests, sendRequests endpoint,
// discount support, then full payment and cleanup.
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
  const rich = await login('rich@minipay.test');
  const friend = await login('friend@minipay.test');
  const users = await (await get('/admin/users', rich)).json();
  const friendId = users.find((u) => u.email === 'friend@minipay.test').id;

  // 1. Create: creator included server-side. 2 items, 1 assigned to friend.
  const createRes = await post('/split', {
    title: 'Flow Check',
    participantUserIds: [friendId],
    items: [
      { name: 'Main', priceMinor: 3000 },
      { name: 'Dessert', priceMinor: 1000, assignedUserIds: [friendId] },
    ],
    extraMinor: -200, // discount the AI missed
  }, rich);
  const created = await createRes.json();
  const creatorPart = created.participants.find((x) => x.isCreator === true);
  const friendPart = created.participants.find((x) => x.userId === friendId);
  console.log('created:', createRes.status);
  console.log('creator participant present:', !!creatorPart, '| isCreator:', creatorPart?.isCreator, '| share:', creatorPart?.shareAmount, '| status:', creatorPart?.status);
  console.log('friend share:', friendPart?.shareAmount, '| requestId null (not sent yet):', friendPart?.requestId === null);

  // Expected: total 4000-200=3800. Main 3000/2=1500 each. Dessert 1000 friend.
  // Discount -200/2 = -100 each. rich: 1400, friend: 2400.
  console.log('creator share == 1400:', creatorPart?.shareAmount === '1400');
  console.log('friend share == 2400:', friendPart?.shareAmount === '2400');

  // 2. No requests sent yet
  const reqs = await (await get('/requests', friend)).json();
  const pendingBefore = reqs.toMe.filter((r) => r.status === 'PENDING').length;
  console.log('friend pending requests (expect unchanged):', pendingBefore);

  // 3. Send request to friend from detail
  const send = await post(`/split/${created.id}/requests/send`, { userIds: [friendId] }, rich);
  console.log('send:', (await send.json()).sent === 1 ? 'OK' : 'FAIL');

  // 4. Friend pays
  const mine = await (await get('/requests', friend)).json();
  const pr = mine.toMe.find((r) => r.id && r.status === 'PENDING' && r.note && r.note.includes('Flow Check'));
  const pay = await post(`/requests/${pr.id}/pay`, { pin: '123456' }, friend);
  console.log('friend paid:', pay.status === 200 || pay.status === 201);

  // 5. Detail now shows SETTLED + creator PAID
  const detail = await (await get(`/split/${created.id}`, rich)).json();
  console.log('detail status:', detail.status, '| paidMinor:', detail.paidMinor, '| pendingMinor:', detail.pendingMinor);
  console.log('friend status:', detail.participants.find((x) => x.userId === friendId).status);

  // 6. Invariant
  const inv = await (await get('/ledger/invariant', rich)).json();
  console.log('ledger invariant ok:', inv.ok);

  // 7. Cleanup test data
  await p.moneyRequest.deleteMany({ where: { splitSessionId: created.id } });
  await p.splitSession.delete({ where: { id: created.id } });
  console.log('cleaned up test split');
  await p.$disconnect();
})().catch((e) => { console.error(e); process.exit(1); });
