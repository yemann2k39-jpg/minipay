# Merchant Account Management — Handoff & Design Notes

**For**: a new session picking up merchant-management features for MiniPay.
**Purpose**: explain what already exists, what's missing, and the open design
questions — so we can discuss what to build **without breaking the working app**.

> Read together with `docs/MERCHANT-INTEGRATION.md` (the universal website
> integration guide — API contract, hosted checkout, callbacks). This file
> covers everything else: the current merchant implementation, its gaps, and
> the design space for admin/user control of merchant accounts.

---

## 1. Project snapshot (as of this handoff)

MiniPay is a working mobile wallet (Flutter + NestJS + PostgreSQL + Stripe test
mode). **14 tickets done** across: auth (JWT rotation + payment PIN), deposits
(Stripe webhook), QR merchant payments, P2P transfers, money requests, split
bills (Gemini receipt scan), history/reports, admin dashboard (React), app
lock (biometric/PIN), success + transaction detail pages, and the merchant
checkout gateway (API keys, hosted checkout page, HMAC callbacks).

Environment: Windows laptop. Postgres 16 in Docker (port **5434** — NOT 5432,
a native Windows Postgres owns that). NestJS dev server on **:3000** (watch
mode). Admin dashboard on **:5174** (5173 was taken). Stripe CLI forwards
webhooks to `:3000/payments/webhook`. Phone tests run over USB with
`adb reverse tcp:3000 tcp:3000` — the Flutter app calls `localhost:3000`,
which tunnels to the laptop. Full details: `minipay-architecture.md` in
`C:\KuromiLab`.

Git: all work committed through the split v2 + merchant gateway feature
(`0c6d5358`, then uncommitted merchant-gateway polish — commit pending user
confirmation). Ticket workflow: `tickets` CLI in the repo root (PGW-1…14 done,
PGW-15/16 in progress, PGW-9 backlog).

---

## 2. How merchants work TODAY (do not break this)

### 2.1 Data model (prisma/schema.prisma)

```
Merchant {
  id, code (MP-XXXXXXXX, unique), name, status (ACTIVE|FROZEN|CLOSED)
  apiKeyHash String? @unique     // SHA-256 of the API key — lookup only
  apiKey      String?            // PLAIN key stored for callback signing.
                                 // PRODUCTION: must be encrypted at rest.
  callbackUrl String?            // where signed payment callbacks POST
  ledgerAccountId / ledgerAccount  // dedicated MERCHANT-kind ledger account
}

LedgerAccount kind MERCHANT            // the shop's settlement pot
CheckoutSession {                      // one per website order
  merchantId, orderRef (unique per merchant), amountMinor, description,
  status (PENDING|PAID|EXPIRED), callbackUrl, transactionId, expiresAt, paidAt
}
```

Key facts:
- **Merchants are NOT Users.** Separate model, separate ledger account, no app
  login, no PIN. A shop cannot send money, only receive (today).
- The shop's **balance = sum of its MERCHANT ledger account lines**. Every
  checkout payment debits the payer's WALLET and credits the MERCHANT account
  (double-entry, idempotency key `checkout_<sessionId>`).
- The plain API key is stored because payment callbacks are HMAC-signed with
  it (`X-MiniPay-Signature` = HMAC_SHA256(rawBody, apiKey)). Production must
  encrypt it at rest — there's a schema comment saying so.

### 2.2 The payment flow (works end-to-end, verified)

```
Website backend → POST /merchant-api/checkout (X-API-Key)
                  { orderRef, amountMinor, description, callbackUrl }
← { checkoutId, checkoutUrl: /checkout/<id>, expiresAt (15 min) }

Customer browser → GET /checkout/<id>/page   (hosted HTML page, no-store)
  - QR encoding minipay://checkout/<id>  → MiniPay app scans (PGW-16)
  - email + PIN form                     → POST /checkout/<id>/pay-web
App path → POST /checkout/:id/pay (JWT + {pin})
Both → verify PIN → balance check → ledger post → session PAID
     → HMAC-signed callback POST to merchant callbackUrl (retries 2s/5s/10s)
```

- Idempotent: same (merchantId, orderRef) while PENDING returns the existing
  session (200); PAID under the same orderRef → 409.
- Lazy expiry: reading a PENDING session past `expiresAt` marks it EXPIRED.
- Frozen/closed customers are rejected at pay time. Merchants have no frozen
  policy wired yet.

### 2.3 Endpoints that exist

| Route | Auth | Purpose |
|---|---|---|
| POST /merchant-api/checkout | X-API-Key | Create/idempotent-get session |
| GET /merchant-api/checkout/:id | X-API-Key | Status polling (lazy expiry) |
| GET /checkout/:id | public | JSON status (for hosted page JS) |
| GET /checkout/:id/page | public | Hosted checkout HTML |
| POST /checkout/:id/pay | JWT | App payment (customer's PIN) |
| POST /checkout/:id/pay-web | public | Hosted-page email+PIN payment |
| GET /merchants/:code + /qr.png | public | Merchant QR (in-person payments) |
| POST /admin/merchants | admin | Create merchant (API key returned ONCE) |
| GET /admin/merchants | admin | List (no keys) |
| POST /admin/merchants/:id/rotate-key | admin | New API key (old dies) |

Merchants seeded today: PC Shop, Bedok Books, Kopi Tiam SG, Popato Snacks
(see `apps/api/scripts/seed-merchants.js` and the smoke scripts
`verify-checkout.js`, `demo-callback-listener.js`, `demo-create-checkout.js`).

---

## 3. What's MISSING (the design space for this feature)

The core gap: **merchants can receive money but cannot see or manage it.**

1. **No merchant login/portal.** The shop cannot see its balance, its
   payments, or its checkout history anywhere.
2. **No payouts.** Money accumulates in the merchant ledger account forever.
   No withdrawal, no settlement, no transfer to a bank or wallet.
3. **No merchant visibility in the admin dashboard.** Admin sees users with
   balances, but merchants and their balances aren't listed; freeze/unfreeze
   doesn't cover merchants.
4. **No owner linkage.** A Merchant has no connection to any User — so the app
   can't show "your shop" to anyone.
5. **No refunds.** A merchant can't push money back to a customer.
6. Minor: merchant balance isn't in any API response; no merchant-facing
   notifications.

---

## 4. Prior design discussion (where the parent session landed)

Three options were discussed for merchant money management:

- **A. Admin payouts** — admin endpoint moves shop balance to any wallet.
  Simplest; manual settlement.
- **B. Owner-linked withdrawal (recommended by parent)** — link each Merchant
  to an owner `User`; the owner sees shop balance in the MiniPay app and taps
  "Withdraw to my wallet" (internal double-entry transfer MERCHANT → WALLET).
  The GrabPay-style pattern; medium effort.
- **C. Full merchant portal** — separate merchant login + dashboard. Large.

The parent session stopped here intentionally — the new session should
**discuss with the user** which option(s) to build before writing code.

---

## 5. Constraints — what must NOT break

1. **Ledger invariants**: shares/postings must always balance
   (`GET /ledger/invariant` must stay `ok: true`). Any new money movement must
   be a balanced journal entry (see `ledger.service.ts` — note the
   asset-vs-liability direction handling; this caused two real bugs).
2. **Idempotency**: every money movement carries a unique idempotency key.
   Payouts/refunds need their own keys.
3. **Frozen policy**: FROZEN users can't initiate money movement but CAN
   receive. Decide (and implement consistently) what FROZEN means for
   merchants.
4. **The MERCHANT ledger direction pitfall**: the balance check respects each
   account kind's natural direction — `MERCHANT` is credit-positive like
   `WALLET` (fixed once, don't regress).
5. **API keys**: plain key exists only for callback HMAC signing; keys are
   returned once at creation/rotation. Anything new must not log or leak them.
6. **Don't touch the documented contract** in
   `docs/MERCHANT-INTEGRATION.md` without updating it in the same change —
   external websites depend on it.
7. **Existing app patterns**: Flutter uses `ApiClient.instance.dio`,
   `apiError(e).message`, SuccessScreen, colored status chips, SafeArea
   (edge-to-edge). NestJS: modules per domain, JwtAuthGuard + role guards,
   `flutter analyze` and `tsc --noEmit` must stay clean.

---

## 6. Useful entry points

| File | Why |
|---|---|
| `apps/api/src/merchants/merchants.service.ts` | merchant CRUD, key gen, QR |
| `apps/api/src/merchant-api/*` | API-key guard + checkout create/poll |
| `apps/api/src/checkout/checkout.service.ts` | payment execution + callbacks |
| `apps/api/src/ledger/ledger.service.ts` | the money engine |
| `apps/api/src/admin/*` | admin dashboard API |
| `apps/admin/src/pages/*` | admin UI (add merchant pages here) |
| `apps/mobile/lib/screens/home_screen.dart` | app entry points live here |
| `docs/MERCHANT-INTEGRATION.md` | the website-facing contract |
| `apps/api/scripts/verify-checkout.js` | live end-to-end smoke test |

---

## 7. Open questions to discuss with the user first

1. Which management model: A (admin payouts), B (owner-linked withdrawal), or
   C (full portal)? Parent leaned B.
2. Should merchants get a role on `User` (e.g. role = MERCHANT) or stay a
   separate identity with a linked owner User?
3. Settlement timing: instant withdraw, or a pending-settlement period?
4. Fees: does MiniPay take a cut on checkout payments (affects ledger
   postings — FEES account exists but is unused)?
5. Refunds: full/partial? Who initiates?
