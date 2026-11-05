// Demo callback receiver: logs + HMAC-verifies callbacks on :3999.
const crypto = require('crypto');
const http = require('http');
const API_KEY = process.argv[2];
const received = [];
const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    const expected = crypto.createHmac('sha256', API_KEY).update(body).digest('hex');
    const valid = req.headers['x-minipay-signature'] === expected;
    received.push({ body: JSON.parse(body), valid });
    console.log(`CALLBACK received | HMAC valid: ${valid} | event: ${body.event} | orderRef: ${body.orderRef} | amountMinor: ${body.amountMinor}`);
    res.writeHead(200).end('{"ok":true}');
  });
});
server.listen(3999, () => console.log('callback demo listener ready on :3999'));
setInterval(() => {}, 1 << 30); // keep alive
