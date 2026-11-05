// Debug: retry checkout creation, print raw status + body.
const BASE = 'http://localhost:3000';
(async () => {
  const r = await fetch(BASE + '/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'rich@minipay.test', password: 'Passw0rd!23' }),
  });
  const t = (await r.json()).accessToken;
  const merchants = await (await fetch(BASE + '/admin/merchants', { headers: { Authorization: `Bearer ${t}` } })).json();
  console.log('merchants:', JSON.stringify(merchants).slice(0, 500));

  // Find the PC Shop API key: we can't recover it (hashed) — rotate it.
  const shop = merchants.find((m) => m.name === 'PC Shop');
  if (!shop) { console.log('PC Shop merchant missing'); return; }
  const rk = await fetch(BASE + `/admin/merchants/${shop.id}/rotate-key`, {
    method: 'POST', headers: { Authorization: `Bearer ${t}` },
  });
  const keyBody = await rk.json();
  console.log('rotate-key status:', rk.status, '| has key:', !!keyBody.apiKey);
  const apiKey = keyBody.apiKey;

  const cr = await fetch(BASE + '/merchant-api/checkout', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-API-Key': apiKey },
    body: JSON.stringify({
      orderRef: 'ORDER-SMOKE-2',
      amountMinor: 15900,
      description: 'GPU cable + case fan',
      callbackUrl: 'http://localhost:3999/cb',
    }),
  });
  console.log('checkout status:', cr.status);
  console.log('body:', JSON.stringify(await cr.json()).slice(0, 400));
})().catch((e) => console.error(e));
