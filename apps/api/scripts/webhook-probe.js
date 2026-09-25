// Standalone probe: signs a fake payment_intent.succeeded payload with the
// same webhook secret (Stripe v1 scheme) and posts it to the local API.
const crypto = require('crypto');
const http = require('http');

const whsec = 'whsec_5fa67e6e634f3f7d620e6666a135ac39ad6c923fb8de26c8fca260be36c09d34';

const payload = JSON.stringify({
  id: 'evt_test_local',
  object: 'event',
  api_version: '2026-08-26.dahlia',
  created: Math.floor(Date.now() / 1000),
  data: { object: { id: 'pi_local_test', object: 'payment_intent' } },
  livemode: false,
  pending_webhooks: 1,
  request: { id: null, idempotency_key: null },
  type: 'payment_intent.succeeded',
});

const timestamp = Math.floor(Date.now() / 1000);
const toSign = `${timestamp}.${payload}`;
const v1 = crypto.createHmac('sha256', whsec).update(toSign, 'utf8').digest('hex');
const sig = `t=${timestamp},v1=${v1}`;

const req = http.request(
  {
    host: '127.0.0.1',
    port: 3000,
    path: '/payments/webhook',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(payload),
      'Stripe-Signature': sig,
    },
  },
  (res) => {
    let body = '';
    res.on('data', (c) => (body += c));
    res.on('end', () => {
      console.log('STATUS:', res.statusCode);
      console.log('BODY:', body);
    });
  },
);
req.on('error', (e) => console.error('REQ ERROR', e));
req.write(payload);
req.end();
