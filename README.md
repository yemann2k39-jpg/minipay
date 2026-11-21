# MiniPay

MiniPay is a digital wallet and merchant payment gateway. A single Flutter app serves both consumers and merchants, backed by a NestJS REST API and PostgreSQL. A React admin dashboard is used for platform management.

All money movement is recorded in a double-entry ledger. Balances are never stored directly; they are derived from journal lines, and an endpoint verifies at any time that every entry in the books balances.

## Features

- P2P transfers by email or contact lookup, authorized with fingerprint or a 6-digit payment PIN, with server-enforced daily spend limits
- QR payments: scan a merchant's collect-payment QR, or show a personal QR to receive money
- Merchant mode: register a business in-app, collect payments, view sales history, issue full refunds, withdraw balance to the owner's wallet
- Hosted checkout and a public REST API for external merchants, authenticated with API keys and confirmed through HMAC-SHA256 signed webhooks
- Card deposits through Stripe, where the signature-verified webhook is the only path that credits a wallet
- Money requests, bill splitting with receipt scanning, monthly spending reports, and shareable transaction receipts
- Security: rotating refresh-token sessions with device tracking, bcrypt-hashed passwords and PINs, biometric app unlock, and role-based access control with frozen-account enforcement

## How the pieces fit together

The Flutter app talks to the NestJS API over REST using JWT access tokens with rotating refresh sessions. The API is the single source of truth. Every money movement goes through the ledger service, which posts balanced journal lines inside a database transaction. Idempotency keys and per-account Postgres advisory locks ensure that concurrent transfers and retried webhooks cannot post twice.

The gateway flow works like this: a merchant creates a checkout session through the API or an in-app QR code, the customer scans it and confirms payment in the app or on a hosted checkout page, the API records the ledger entry, and the merchant receives a signed callback.

Deposits follow the same discipline. The client confirms a card payment with Stripe, but the wallet is only credited when the signed `payment_intent.succeeded` webhook arrives. Refunds claim a sale through a conditional status transition; if the ledger write fails, the claim rolls back.

## Tech stack

- Mobile app: Flutter (flutter_secure_storage, mobile_scanner, local_auth, fl_chart, qr_flutter, flutter_local_notifications, share_plus)
- API: NestJS with TypeScript, Passport JWT, class-validator, Stripe SDK
- Database: PostgreSQL 16 with Prisma ORM
- Admin dashboard: React with Vite and TypeScript
- Local infrastructure: Docker Compose for PostgreSQL, Stripe test mode

## Repository layout

- `apps/api` — NestJS REST API
- `apps/mobile` — Flutter app
- `apps/admin` — React admin dashboard
- `docs` — merchant integration guide and handoff documents

## Getting started

Prerequisites: Node.js 20+, pnpm, Flutter 3.x, and Docker.

Start the database and apply the schema:

```
docker compose up -d
cd apps/api
npx prisma db push
```

Create `apps/api/.env` with `DATABASE_URL`, `JWT_SECRET`, `STRIPE_SECRET_KEY` (test mode), and `STRIPE_WEBHOOK_SECRET` (the secret printed by `stripe listen`). Then run the API:

```
pnpm install
pnpm start:dev
```

Run the mobile app against the local API:

```
cd apps/mobile
flutter pub get
flutter run
```

Run the admin dashboard:

```
cd apps/admin
npm install
npm run dev
```

## Testing

```
cd apps/api
npx jest
```

`GET /ledger/invariant` returns `ok: true` when every journal entry balances. `node scripts/verify-checkout.js` runs the full gateway flow end to end: checkout creation, API key auth, the hosted page, in-app payment, HMAC callback verification, and the ledger invariant check. Static checks are `flutter analyze` for the app and `npx nest build` for the API.

## Implementation notes

- Amounts are BigInt minor units throughout; no floats are used for money.
- Refresh tokens and merchant API keys are stored as SHA-256 hashes. A plaintext key is shown only once, at creation.
- Frozen accounts are receive-only, enforced at the endpoint level.
- Merchant callbacks are signed as `X-MiniPay-Signature`, an HMAC-SHA256 over the raw request body, with exponential retry backoff.

## Status

The project is feature-complete for personal and merchant flows against Stripe test mode. It is not yet production-hardened: there is no CI pipeline, only one currency is supported, fees are not modeled, and callback delivery happens in-process rather than through a persistent outbox.

## Documentation

- `docs/MERCHANT-INTEGRATION.md` — integrating with the merchant API
- `docs/MERCHANT-MANAGEMENT-HANDOFF.md` — merchant lifecycle management
