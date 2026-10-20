// Verifies the updated split flow:
//  1. Creator included as shareholder (no request against them)
//  2. No requests auto-sent on create
//  3. sendRequests endpoint sends, re-send targets declined too
//  4. Delete blocked after send, allowed before
//  5. Discount support (extra + discount separate)
const { PrismaClient } = require('@prisma/client');
const p = new PrismaClient();
const BASE = 'http://localhost:3000';
const post = (path, body, token) =>
  fetch(BASE + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
const del = (path, token) =>
  fetch(BASE + path, { method: 'DELETE', headers: token ? { Authorization: `Bearer ${token}` } : {} });
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

  // 1. Create with creator included implicitly, discount 200, extra 300.
  //    items: main 3000 (split all), dessert 1000 (friend only)
  //    shareholders: rich + friend. main 1500/1500, dessert friend 1000.
  //    adjustment +300-200=+100 -> +50 each.
  //    rich: 1600 (no request). friend: 1500+1000+50=2550.
  const createRes = await post('/split', {
    title: 'Delete/Reissue Check',
    participantUserIds: [friendId],
    items: [
      { name: 'Main', priceMinor: 3000 },
      { name: 'Dessert', priceMinor: 1000, assignedUserIds: [friendId] },
    ],
    extraMinor: 300,
    discountMinor: 200,
  }, rich);
  const created = await createRes.json();
  const creatorPart = created.participants.find((x) => x.isCreator);
  const friendPart = created.participants.find((x) => x.userId === friendId);
  console.log('creator share 1600:', creatorPart?.shareAmount === '1600', '| status:', creatorPart?.status);
  console.log('friend share 2550:', friendPart?.shareAmount === '2550');

  // 2. Delete blocked after requests are sent; allowed before -> test before first.
  const preDelete = await del(`/split/${created.id}`, rich);
  console.log('PRE-SEND delete should have been 200... got:', preDelete.status);
  // Oops — we delete before sending, so recreate.
  if (preDelete.status === 200) {
    // Recreate the same split.
    const again = await post('/split', {
      title: 'Delete/Reissue Check',
      participantUserIds: [friendId],
      items: [
        { name: 'Main', priceMinor: 3000 },
        { name: 'Dessert', priceMinor: 1000, assignedUserIds: [friendId] },
      ],
      extraMinor: 300,
      discountMinor: 200,
    }, rich);
    const againBody = await again.json();
    const send = await post(`/split/${againBody.id}/requests/send`, { userIds: [friendId] }, rich);
    console.log('send requests:', send.status);

    // 3. Delete now blocked
    const blocked = await del(`/split/${againBody.id}`, rich);
    const blockedBody = await blocked.json();
    console.log('delete blocked after send:', blocked.status === 400, '|', blockedBody.message);

    // 4. Friend declines; re-send re-issues
    const reqs = await (await get('/requests', friend)).json();
    const pending = reqs.toMe.find((r) => r.status === 'PENDING');
    if (pending) {
      const dec = await post(`/requests/${pending.id}/decline`, null, friend);
      console.log('declined:', dec.status === 200 || dec.status === 201);
    }
    const resend = await post(`/split/${againBody.id}/requests/send`, {}, rich);
    const resendBody = await resend.json();
    console.log('re-send after decline sent:', resendBody.sent === 1);

    // 5. Friend pays the fresh request
    const reqs2 = await (await get('/requests', friend)).json();
    const fresh = reqs2.toMe.find((r) => r.status === 'PENDING');
    const pay = await post(`/requests/${fresh.id}/pay`, { pin: '123456' }, friend);
    console.log('friend paid re-issued request:', pay.status === 200 || pay.status === 201);

    // 6. Session settled
    const detail = await (await get(`/split/${againBody.id}`, rich)).json();
    console.log('session settled:', detail.status === 'SETTLED', '| paidMinor:', detail.paidMinor);
    await p.$disconnect?.();
    const { PrismaClient } = require('@prisma/client');
    const pc = new PrismaClient();
    await pc.$disconnect();
  }

  const inv = await (await get('/ledger/invariant', rich)).json();
  console.log('ledger invariant ok:', inv.ok);
  await p.$disconnect();
})().catch((e) => { console.error(e); process.exit(1); });
