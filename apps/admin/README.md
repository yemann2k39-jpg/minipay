# Wallet Admin

Internal admin dashboard for the payment wallet backend.

## Stack

- Vite + React + TypeScript (plain CSS, no UI libraries)
- Dev server on port **5173** (Vite default)

## Getting started

```bash
npm install
npm run dev
```

## Backend / API access

The backend is a NestJS API at `http://localhost:3000`. All requests from this
app use relative `/api/...` paths (see `src/api.ts`), which the Vite dev server
proxies to the backend (see `server.proxy` in `vite.config.ts`), avoiding CORS.

Authenticated calls send `Authorization: Bearer <accessToken>`. The access
token is kept in memory and mirrored to `localStorage`; any 401 clears it and
returns the app to the login page.

## Build

```bash
npm run build   # type-checks (tsc -b) then bundles with Vite
```

## Structure

- `src/api.ts` — small API client (token handling, error extraction, endpoints)
- `src/types.ts` — shared API types
- `src/format.ts` — money (`fmt`), date, and short-id helpers
- `src/pages/` — Login, Dashboard, Users, Transactions
- `src/components/StatusBadge.tsx` — colored status badges
- `src/styles.css` — all styling (white surfaces, deep blue `#0F4C81`, page bg `#F5F7FA`)
