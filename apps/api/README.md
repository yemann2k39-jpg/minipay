# MiniPay API

NestJS REST API for the MiniPay wallet and merchant payment gateway. This service is the source of truth: every balance is derived from a double-entry ledger, and every money movement posts a balanced journal entry inside a database transaction.

## Modules

| Module        | Responsibility |
|---------------|----------------|
| `auth`        | JWT access + rotating refresh-token sessions (hashed, device metadata), bcrypt passwords, 6-digit payment PINs (set/change/reset), profile, preferences (daily spend limit) |
| `wallet`      | Balance, paginated history, monthly report, Stripe PaymentIntent deposits (webhook is the single credit writer) |
| `ledger`      | Double-entry engine: idempotent journal posting, advisory locks, balance queries, `GET /ledger/invariant` |
| `transfers`   | P2P transfers with server-enforced daily spend limits |
| `contacts`    | Contact management + email lookup for transfers |
| `requests`    | Money requests (pay / decline / cancel) |
| `split`       | AI receipt scanning (Gemini) + bill splitting with share requests |
| `merchants`   | Merchant mode: collect-payment sessions, sales history, refunds, payouts (withdraw to wallet), API key management |
| `merchant-api`| Public hosted-checkout REST API (X-API-Key auth) |
| `checkout`    | Checkout sessions, hosted checkout page, in-app/web payment |
| `payments`    | Merchant QR payments + Stripe webhook (signature-verified) |
| `notifications` | Money-event notifications (bell + unread counts) |
| `admin`       | Platform management: users, merchants, transactions, stats (ADMIN role) |

## Setup

```bash
pnpm install
npx prisma db push        # requires PostgreSQL from repo-root docker-compose
pnpm start:dev            # http://localhost:3000
```

Environment variables (`.env`): `DATABASE_URL`, `JWT_SECRET`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `GEMINI_API_KEY` (optional).

## Verification

```bash
npx jest                              # unit tests
curl localhost:3000/ledger/invariant  # books balance check (admin JWT)
node scripts/verify-checkout.js       # end-to-end gateway flow
```

## Notable Implementation Details

- **Idempotency keys** on every ledger post (`tx_<id>`, `pi_<paymentIntentId>`) make retries safe.
- **Sorted advisory locks** per account prevent deadlocks between concurrent journal writes.
- **Deposits** are credited only by the signature-verified `payment_intent.succeeded` webhook — the raw request body is preserved for HMAC verification.
- **Refunds** flip the sale `PAID → REFUNDED` with one conditional update; ledger failure rolls the claim back.
- **Frozen accounts** are receive-only, enforced at the endpoint level.
- `merchants/:code/qr.png` renders the collect-payment QR server-side.

See the repo root README for architecture and the full stack overview.
