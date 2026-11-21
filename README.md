# MiniPay — Digital Wallet & Merchant Payment Gateway

A mobile-first digital wallet and merchant payment gateway built on a double-entry ledger core. One Flutter app serves both consumers and merchants; a NestJS REST API with PostgreSQL is the source of truth; a React admin dashboard handles platform management.

## Highlights

- **Double-entry ledger** — every money movement posts balanced journal lines. Balances are derived from the ledger, never stored, and a `/ledger/invariant` endpoint proves the books always balance.
- **P2P transfers** — pay by email or contact lookup, authorize with fingerprint or a 6-digit payment PIN, protected by server-enforced daily spend limits.
- **Merchant gateway** — in-app business registration, collect-payment QR sessions, a hosted checkout page, and a public REST API authenticated with API keys.
- **HMAC-signed webhooks** — merchants receive `X-MiniPay-Signature` (HMAC-SHA256 over the raw body) callbacks with exponential retry backoff.
- **Refunds & payouts** — atomic refund claims with automatic ledger rollback on failure; withdraw-to-wallet payouts.
- **Card deposits** — Stripe PaymentIntents; the signature-verified webhook is the single writer that credits wallets.
- **Security** — rotating refresh-token sessions with device tracking, bcrypt-hashed passwords and PINs, biometric app unlock, role-based access control with frozen-account enforcement.
- **Insights & reports** — merchant sales analytics (daily/weekly aggregates + 7-day chart), monthly wallet reports, shareable receipts.

## Architecture

```
┌──────────────────┐   REST + JWT   ┌──────────────────────────────┐
│  Flutter app     │ ◄────────────► │  NestJS API (:3000)          │
│  (consumer +     │                │  auth · wallet · ledger ·    │
│   merchant mode) │                │  transfers · merchants ·     │
└──────────────────┘                │  merchant-api · checkout ·   │
┌──────────────────┐   REST + JWT   │  payments · admin · requests │
│  React admin     │ ◄────────────► │  split · contacts · notifs   │
│  dashboard       │                └──────────┬───────────────────┘
└──────────────────┘                           │ Prisma
                                     ┌─────────▼─────────┐
   Stripe ── webhook (signed) ─────► │  PostgreSQL 16    │
   Merchants ◄── HMAC callbacks ──── └───────────────────┘
```

All money movements go through the ledger service inside database transactions, protected by idempotency keys and per-account Postgres advisory locks — concurrent transfers and retried webhooks can never double-post.

## Tech Stack

| Layer      | Tech |
|------------|------|
| Mobile app | Flutter, flutter_secure_storage, mobile_scanner, local_auth, fl_chart, qr_flutter, flutter_local_notifications, share_plus |
| API        | NestJS (TypeScript), Passport JWT, class-validator, Stripe SDK |
| Database   | PostgreSQL 16, Prisma ORM |
| Admin      | React 18 + Vite, TypeScript |
| Dev infra  | Docker Compose (Postgres), Stripe test mode |

## Repository Layout

```
apps/api      NestJS REST API (the source of truth)
apps/mobile   Flutter app (personal + business modes)
apps/admin    React admin dashboard
docs          Merchant integration guide & handoff docs
```

## Getting Started

### Prerequisites

- Node.js 20+, pnpm
- Flutter 3.x
- Docker (for PostgreSQL)

### 1. Database

```bash
docker compose up -d          # PostgreSQL 16 on localhost:5434
cd apps/api
npx prisma db push            # apply schema
```

### 2. API

Create `apps/api/.env`:

```
DATABASE_URL=postgresql://user:pass@localhost:5434/minipay
JWT_SECRET=<random hex>
STRIPE_SECRET_KEY=sk_test_...            # Stripe test mode
STRIPE_WEBHOOK_SECRET=whsec_...          # from `stripe listen`
GEMINI_API_KEY=...                       # optional: AI receipt split
```

```bash
pnpm install
pnpm start:dev                # API on http://localhost:3000
```

### 3. Mobile app

```bash
cd apps/mobile
flutter pub get
flutter run                   # point the app at http://localhost:3000
```

### 4. Admin dashboard

```bash
cd apps/admin
npm install
npm run dev                   # http://localhost:5174
```

## Testing & Verification

- **Unit tests** — `cd apps/api && npx jest`
- **Ledger invariant** — `GET /ledger/invariant` returns `ok: true` when every journal entry balances
- **End-to-end gateway flow** — `node apps/api/scripts/verify-checkout.js` exercises checkout creation, API-key auth, the hosted page, in-app payment, HMAC callback verification, and the ledger invariant
- **Static analysis** — `flutter analyze`, `npx nest build`

## Documentation

- [`docs/MERCHANT-INTEGRATION.md`](docs/MERCHANT-INTEGRATION.md) — integrating with the merchant API (checkouts, API keys, webhook verification)
- [`docs/MERCHANT-MANAGEMENT-HANDOFF.md`](docs/MERCHANT-MANAGEMENT-HANDOFF.md) — merchant lifecycle management

## Design Notes

- Amounts are **BigInt minor units** (SGD cents) end-to-end — no floats.
- The **Stripe webhook is the single writer** that credits wallets from deposits; client confirmations never move money.
- Refresh tokens and merchant API keys are stored as **SHA-256 hashes**; the plaintext key is shown only once at creation.
- Refund claims use a **conditional PENDING→REFUNDED state transition**; if the ledger write fails, the claim rolls back.

## Status

Feature-complete for personal and merchant flows against Stripe test mode. Not yet production-hardened: no CI/CD pipeline, single currency, zero-fee model, and merchant callbacks are delivered in-process (a persistent outbox is a future improvement).
