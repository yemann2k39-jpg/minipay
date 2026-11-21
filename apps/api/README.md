# MiniPay API

NestJS REST API for the MiniPay wallet and merchant payment gateway. This service is the source of truth: every balance is derived from a double-entry ledger, and every money movement posts a balanced journal entry inside a database transaction.

## Modules

- auth — JWT access tokens with rotating refresh sessions, bcrypt passwords, 6-digit payment PINs (set, change, reset), profile and preferences including the daily spend limit
- wallet — balance, paginated history, monthly report, Stripe PaymentIntent deposits
- ledger — double-entry engine: idempotent journal posting, advisory locks, balance queries, and the invariant check
- transfers — P2P transfers with server-enforced daily spend limits
- contacts — contact management and email lookup
- requests — money requests with pay, decline, and cancel paths
- split — receipt scanning and bill splitting with share requests
- merchants — merchant mode: collect-payment sessions, sales history, refunds, payouts, API key management
- merchant-api — public hosted-checkout REST API authenticated with API keys
- checkout — checkout sessions, hosted checkout page, in-app and web payment
- payments — merchant QR payments and the Stripe webhook
- notifications — money-event notifications with unread counts
- admin — platform management for users, merchants, transactions, and stats

## Setup

Requires PostgreSQL from the repo root docker-compose file.

```
pnpm install
npx prisma db push
pnpm start:dev
```

Environment variables in `.env`: `DATABASE_URL`, `JWT_SECRET`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, and optionally `GEMINI_API_KEY` for receipt scanning.

## Verification

```
npx jest
```

`GET /ledger/invariant` returns `ok: true` when every journal entry balances. `node scripts/verify-checkout.js` runs the full gateway flow end to end, including HMAC callback verification.

## Implementation notes

- Every ledger post carries an idempotency key derived from the transaction or payment intent, so retries are safe.
- Advisory locks are taken per account in sorted order to prevent deadlocks between concurrent journal writes.
- Deposits are credited only by the signature-verified webhook; the raw request body is preserved for HMAC verification.
- Refunds flip a sale from PAID to REFUNDED with a single conditional update. If the ledger write fails, the claim rolls back.
- Frozen accounts are receive-only, enforced at the endpoint level.
- Merchant collect-payment QR codes are rendered server-side at `merchants/:code/qr.png`.

See the root README for the architecture overview and the full tech stack.
