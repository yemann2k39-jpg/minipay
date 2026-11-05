# MiniPay Merchant Integration Guide

Accept **MiniPay** as a payment method on any website. This guide is for
merchants/developers integrating MiniPay Checkout — a hosted, redirect-based
payment flow (the Stripe/PayPal Checkout pattern).

> **Security model**: your website never sees the customer's MiniPay password,
> PIN, or credentials. You create a checkout session with your API key, redirect
> the customer to MiniPay's hosted checkout page, and receive a signed callback
> when the payment completes.

---

## 1. How it works

```
┌──────────┐     1. create checkout      ┌──────────────┐
│ PC Shop  │ ──────────────────────────► │  MiniPay API │
│ backend  │ ◄────────────────────────── │              │
└──────────┘   2. checkoutUrl + id       └──────┬───────┘
     │                                          │
     │ 3. redirect customer                     ▼
     ▼                                   ┌──────────────┐
┌──────────┐    4. pay (QR or email+PIN) │ Hosted page  │
│ Customer │ ──────────────────────────► │  (MiniPay)   │
└──────────┘                             └──────┬───────┘
     │                                          │
     │    5. signed callback (POST)             │ payment recorded
     ▼                                          ▼
┌──────────┐ ◄────────────────────────── ┌──────────────┐
│ PC Shop  │   verify signature,         │  MiniPay API │
│ backend  │   mark order PAID           └──────────────┘
└──────────┘
```

1. Your backend creates a **checkout session** with your API key
   (amount, your order reference, and your callback URL).
2. MiniPay returns a **checkout URL**. Redirect your customer there.
3. The customer pays on MiniPay's hosted page — by scanning a QR with the
   MiniPay app, or entering their MiniPay email + payment PIN.
4. When the payment completes, MiniPay **POSTs a signed callback** to your
   `callbackUrl`. You verify the signature and mark the order paid.
5. You can also **poll** the session status at any time.

---

## 2. Getting started

1. Ask the MiniPay admin to create a merchant account for you
   (name + callback URL). You receive an **API key** (`mp_live_...` /
   `mp_test_...`).
2. Store the API key **server-side only** — never in browser code.
3. All requests use the header `X-API-Key: <your key>`.
4. All amounts are **integer minor units** (cents): SGD 10.00 = `1000`.
5. Base URL: `https://<minipay-host>` (local dev: `http://localhost:3000`).

**Keep your callback endpoint idempotent** — callbacks may occasionally be
retried. Verify the signature, check the checkout status, and update the order
only when transitioning from unpaid → paid.

---

## 3. Create a checkout session

```http
POST /merchant-api/checkout
X-API-Key: <your key>
Content-Type: application/json
```

```json
{
  "orderRef": "ORDER-1024",
  "amountMinor": 15900,
  "description": "Order #1024 — 2x GPU cable, 1x case fan",
  "callbackUrl": "https://yourshop.example.com/minipay/callback"
}
```

| Field | Type | Rules |
|---|---|---|
| `orderRef` | string, ≤ 140 chars | Your unique order reference. Reusing the same `orderRef` while a session is still PENDING returns the existing session (idempotent). |
| `amountMinor` | integer ≥ 1 | Amount in minor units (SGD 159.00 → `15900`). |
| `description` | string, ≤ 280 chars | Shown to the customer on the checkout page. |
| `callbackUrl` | string, HTTPS | MiniPay POSTs the payment result here. |

**Response `201`**

```json
{
  "checkoutId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "checkoutUrl": "http://<minipay-host>/checkout/7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "status": "PENDING",
  "amountMinor": "15900",
  "expiresAt": "2026-10-23T10:15:00.000Z"
}
```

Sessions expire after **15 minutes**. An expired session can no longer be paid —
create a new one.

---

## 4. Redirect the customer

Send the customer's browser to `checkoutUrl`. The hosted page shows the
merchant name, amount, description and a countdown. The customer pays either by:

- scanning the on-page QR with the **MiniPay app** (confirms with
  fingerprint/PIN), or
- entering their **MiniPay email + payment PIN** on the page.

The page refreshes automatically and, on success, shows a payment confirmation.
You may also point the customer back to your site — use
`checkoutUrl + "?returnUrl=<your url>"` — after payment the page links back to it.

---

## 5. Receiving the callback (webhook)

When the payment completes, MiniPay POSTs to your `callbackUrl`:

**Headers**
```
Content-Type: application/json
X-MiniPay-Signature: <hex HMAC-SHA256>
```

**Body**
```json
{
  "event": "checkout.paid",
  "checkoutId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "orderRef": "ORDER-1024",
  "amountMinor": "15900",
  "currency": "SGD",
  "paidAt": "2026-10-23T10:05:31.000Z"
}
```

**Verify the signature** — it is `HMAC_SHA256(rawRequestBody, yourApiKey)`:

```js
// Node.js / Express example
const crypto = require('crypto');

app.post('/minipay/callback',
  express.json({ type: '*/*' }),          // raw body needed for HMAC
  (req, res) => {
    const signature = req.headers['x-minipay-signature'];
    const expected = crypto
      .createHmac('sha256', process.env.MINIPAY_API_KEY)
      .update(req.rawBody)                 // raw request body, not re-serialized
      .digest('hex');

    if (signature !== expected) return res.status(401).end();

    const { event, orderRef, amountMinor } = req.body;
    if (event === 'checkout.paid') {
      markOrderPaid(orderRef, Number(amountMinor)); // your logic
    }
    res.status(200).json({ received: true });
  });
```

Respond `200` to acknowledge. MiniPay retries non-200 callbacks a few times.

---

## 6. Polling the session status (optional)

```http
GET /merchant-api/checkout/<checkoutId>
X-API-Key: <your key>
```

```json
{
  "checkoutId": "7c9e...",
  "orderRef": "ORDER-1024",
  "status": "PAID",
  "amountMinor": "15900",
  "expiresAt": "...",
  "paidAt": "..."
}
```

`status` is one of `PENDING`, `PAID`, `EXPIRED`. Useful for pages that wait
inline, or as a fallback for the callback.

---

## 7. Errors

| Status | Meaning |
|---|---|
| `400` | Invalid request (missing/invalid fields, discount exceeds total) |
| `401` | Missing/invalid API key, or bad callback signature |
| `404` | Unknown checkout id |
| `409` | `orderRef` already exists with a different amount |
| `410` | Checkout session expired |

Errors return `{ "message": "..." }`.

---

## 8. Testing

- MiniPay runs in test mode — no real money moves.
- Frozen/closed customer accounts are rejected with a clear message.
- The customer's payment PIN is verified by MiniPay and never visible to your site.
- Ask the MiniPay admin for a test checkout (or scan the QR with the MiniPay app
  logged in as any test user).

---

## 9. Customer payment methods

| Method | How | Best for |
|---|---|---|
| MiniPay app (QR) | Customer scans the page QR; confirms in-app with fingerprint/PIN | Customers with the app installed |
| Email + PIN | Customer types their MiniPay email + payment PIN on the hosted page | Customers without the app on the same device |

Both record the payment against the customer's wallet and credit the merchant
ledger. Frozen or closed customer accounts are rejected.

---

*Integration questions? Contact the MiniPay admin.*
