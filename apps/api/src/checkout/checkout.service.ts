import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import {
  LedgerAccountKind,
  TransactionStatus,
  TransactionType,
} from '@prisma/client';
import * as QRCode from 'qrcode';
import { AuthService } from '../auth/auth.service';
import { computeCallbackSignature } from '../merchant-api/merchant-api.service';
import { isSessionExpired } from '../merchant-api/merchant-api.service';
import { LedgerService } from '../ledger/ledger.service';
import { PrismaService } from '../prisma/prisma.service';
import { escapeHtml, formatSgd } from './checkout-format';

export { escapeHtml, formatSgd };

const CALLBACK_RETRIES_MS = [2000, 5000, 10000];
const CALLBACK_TIMEOUT_MS = 10_000;

@Injectable()
export class CheckoutService {
  private readonly logger = new Logger(CheckoutService.name);

  constructor(
    private prisma: PrismaService,
    private ledger: LedgerService,
    private auth: AuthService,
  ) {}

  /** Load a session, lazily marking PENDING+expired rows as EXPIRED. */
  async getSessionOrExpire(id: string) {
    const session = await this.prisma.checkoutSession.findUnique({
      where: { id },
      include: { merchant: { select: { id: true, name: true } } },
    });
    if (!session) throw new NotFoundException('Checkout not found');
    if (isSessionExpired(session)) {
      return this.prisma.checkoutSession.update({
        where: { id: session.id },
        data: { status: 'EXPIRED' },
        include: { merchant: { select: { id: true, name: true } } },
      });
    }
    return session;
  }

  /** Public JSON for the hosted page. */
  async publicStatus(id: string) {
    const s = await this.getSessionOrExpire(id);
    return {
      checkoutId: s.id,
      status: s.status,
      merchantName: s.merchant.name,
      amountMinor: s.amountMinor.toString(),
      currency: s.currency,
      description: s.description,
      expiresAt: s.expiresAt,
      ...(s.paidAt ? { paidAt: s.paidAt } : {}),
    };
  }

  /** Customer (JWT) pays a checkout. */
  async pay(userId: string, checkoutId: string, pin: string) {
    return this.executePayment(userId, checkoutId, pin);
  }

  /** Hosted-page email+PIN payment. */
  async payWeb(email: string, checkoutId: string, pin: string) {
    const user = await this.prisma.user.findUnique({
      where: { email: email.trim().toLowerCase() },
    });
    if (!user || user.status === 'CLOSED') {
      throw new NotFoundException('No MiniPay account found with that email');
    }
    return this.executePayment(user.id, checkoutId, pin, user);
  }

  /**
   * Shared payment flow: status checks → PIN → balance → ledger post +
   * session PAID in one atomic step → signed callback (fire-and-forget).
   */
  private async executePayment(
    userId: string,
    checkoutId: string,
    pin: string,
    preloadedUser?: { id: string; status: string },
  ) {
    const session = await this.getSessionOrExpire(checkoutId);
    if (session.status === 'EXPIRED') {
      throw new BadRequestException('This checkout has expired — ask the merchant for a new one');
    }
    if (session.status === 'PAID') {
      throw new ConflictException('This checkout has already been paid');
    }

    const user =
      preloadedUser ??
      (await this.prisma.user.findUnique({ where: { id: userId } }));
    if (!user) throw new NotFoundException('User not found');
    if (user.status === 'FROZEN') {
      throw new ForbiddenException(
        'Your account is frozen. You cannot make payments — contact support for help.',
      );
    }
    if (user.status === 'CLOSED') {
      throw new ForbiddenException('This account is closed');
    }

    await this.auth.verifyPin(user.id, pin);

    // Wallet + friendly insufficient-funds check (the ledger re-checks).
    let wallet = await this.prisma.ledgerAccount.findFirst({
      where: { ownerId: user.id, kind: LedgerAccountKind.WALLET, currency: 'SGD' },
    });
    if (!wallet) {
      wallet = await this.prisma.ledgerAccount.create({
        data: { ownerId: user.id, kind: LedgerAccountKind.WALLET, currency: 'SGD' },
      });
    }
    const balance = await this.ledger.balance(wallet.id);
    if (balance < session.amountMinor) {
      throw new BadRequestException(
        `Insufficient funds — top up in the MiniPay app (balance ${formatSgd(balance)}, need ${formatSgd(session.amountMinor)})`,
      );
    }

    // Atomically transition PENDING → PAID (updateMany guards the race).
    const paidAt = new Date();
    const claim = await this.prisma.checkoutSession.updateMany({
      where: { id: session.id, status: 'PENDING' },
      data: { status: 'PAID', paidAt },
    });
    if (claim.count === 0) {
      throw new ConflictException('This checkout has already been paid');
    }

    const merchantAccount = await this.prisma.merchant.findUniqueOrThrow({
      where: { id: session.merchant.id },
      select: { ledgerAccountId: true },
    });

    const tx = await this.prisma.transaction.create({
      data: {
        type: TransactionType.MERCHANT_PAYMENT,
        status: TransactionStatus.COMPLETED,
        amount: session.amountMinor,
        currency: session.currency,
        fromAccountId: wallet.id,
        toAccountId: merchantAccount.ledgerAccountId,
        completedAt: paidAt,
        meta: { checkoutId: session.id, orderRef: session.orderRef },
      },
    });

    try {
      await this.ledger.post({
        type: 'MERCHANT_PAYMENT',
        description: `Checkout ${session.orderRef} — ${session.merchant.name}`,
        transactionId: tx.id,
        idempotencyKey: `checkout_${session.id}`,
        lines: [
          { accountId: wallet.id, direction: 'DEBIT', amount: session.amountMinor },
          {
            accountId: merchantAccount.ledgerAccountId,
            direction: 'CREDIT',
            amount: session.amountMinor,
          },
        ],
      });
    } catch (e) {
      // Roll the claim back so the checkout stays payable.
      await this.prisma.checkoutSession.updateMany({
        where: { id: session.id, status: 'PAID', transactionId: null },
        data: { status: 'PENDING', paidAt: null },
      });
      await this.prisma.transaction.delete({ where: { id: tx.id } }).catch(() => {});
      throw e;
    }

    await this.prisma.checkoutSession.update({
      where: { id: session.id },
      data: { transactionId: tx.id },
    });

    // Fire-and-forget: never block or fail the customer response on callbacks.
    void this.deliverCallback(session.id, paidAt).catch(() => {});

    return { ok: true, checkoutId: session.id, status: 'PAID', transactionId: tx.id };
  }

  /**
   * HMAC-signed webhook delivery with 10s timeout and retries (2s/5s/10s).
   * Signed with the merchant's plain API key (dev/test stores it in plain
   * text — see the schema comment; production must encrypt at rest).
   */
  async deliverCallback(checkoutId: string, paidAtOverride?: Date) {
    const session = await this.prisma.checkoutSession.findUnique({
      where: { id: checkoutId },
      include: { merchant: { select: { apiKey: true } } },
    });
    if (!session || session.status !== 'PAID' || !session.callbackUrl) return;

    const apiKey = session.merchant.apiKey;
    if (!apiKey) {
      this.logger.error(
        `Checkout ${session.id}: merchant has no API key stored; cannot sign callback`,
      );
      return;
    }

    const body = JSON.stringify({
      event: 'checkout.paid',
      checkoutId: session.id,
      orderRef: session.orderRef,
      amountMinor: session.amountMinor.toString(),
      currency: session.currency,
      paidAt: (paidAtOverride ?? session.paidAt ?? new Date()).toISOString(),
    });
    const signature = computeCallbackSignature(body, apiKey);

    for (let attempt = 0; attempt <= CALLBACK_RETRIES_MS.length; attempt++) {
      if (attempt > 0) {
        await new Promise((r) => setTimeout(r, CALLBACK_RETRIES_MS[attempt - 1]));
      }
      try {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), CALLBACK_TIMEOUT_MS);
        const res = await fetch(session.callbackUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-MiniPay-Signature': signature,
          },
          body,
          signal: controller.signal,
        });
        clearTimeout(timer);
        if (res.ok) {
          this.logger.log(
            `Checkout ${session.id}: callback delivered to ${session.callbackUrl} (200)`,
          );
          return;
        }
        this.logger.warn(
          `Checkout ${session.id}: callback attempt ${attempt + 1} got HTTP ${res.status}`,
        );
      } catch (e: any) {
        this.logger.warn(
          `Checkout ${session.id}: callback attempt ${attempt + 1} failed: ${e?.message ?? e}`,
        );
      }
    }
    this.logger.error(
      `Checkout ${session.id}: callback to ${session.callbackUrl} failed after all retries`,
    );
  }

  /** Server-rendered QR data URI for the hosted page. */
  async qrDataUri(checkoutId: string): Promise<string> {
    return QRCode.toDataURL(`minipay://checkout/${checkoutId}`, {
      width: 240,
      margin: 1,
      color: { dark: '#0F4C81', light: '#FFFFFF' },
    });
  }

  /** The hosted checkout page (public, no-store). */
  async renderPage(checkoutId: string, returnUrl?: string): Promise<string> {
    const s = await this.getSessionOrExpire(checkoutId);
    const merchantName = escapeHtml(s.merchant.name);
    const description = s.description ? escapeHtml(s.description) : '';
    const amount = escapeHtml(formatSgd(s.amountMinor));
    const id = escapeHtml(s.id);

    const head = `<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${merchantName} — MiniPay Checkout</title>
<style>
  * { box-sizing: border-box; margin: 0; }
  body { font-family: 'Segoe UI', system-ui, -apple-system, sans-serif; background: #eef2f6; min-height: 100vh;
         display: flex; align-items: center; justify-content: center; padding: 24px; }
  .card { background: #fff; border-radius: 16px; box-shadow: 0 12px 40px rgba(15,76,129,.18);
          max-width: 420px; width: 100%; padding: 32px; }
  .brand { color: #0F4C81; font-weight: 700; letter-spacing: .5px; font-size: 14px; text-transform: uppercase; }
  .merchant { font-size: 20px; font-weight: 600; color: #1a2733; margin-top: 8px; }
  .desc { color: #5a6b7b; font-size: 14px; margin-top: 4px; }
  .amount { color: #0F4C81; font-size: 40px; font-weight: 700; margin: 20px 0 4px; }
  .expiry { color: #8494a5; font-size: 13px; }
  .divider { border: 0; border-top: 1px solid #e4eaf0; margin: 24px 0; }
  h3 { font-size: 13px; color: #5a6b7b; text-transform: uppercase; letter-spacing: .5px; margin-bottom: 12px; }
  .qr { display: block; margin: 0 auto; border: 1px solid #e4eaf0; border-radius: 12px; padding: 8px; }
  .qr-hint { text-align: center; color: #8494a5; font-size: 12px; margin-top: 8px; }
  label { display: block; font-size: 13px; color: #33475b; margin: 12px 0 4px; }
  input { width: 100%; padding: 10px 12px; border: 1px solid #cfd9e2; border-radius: 8px; font-size: 15px; }
  input:focus { outline: 2px solid #0F4C81; border-color: #0F4C81; }
  button { width: 100%; margin-top: 16px; background: #0F4C81; color: #fff; border: 0; border-radius: 8px;
           padding: 12px; font-size: 15px; font-weight: 600; cursor: pointer; }
  button:disabled { opacity: .6; cursor: default; }
  .error { display: none; margin-top: 12px; background: #fdecea; color: #b3261e; border: 1px solid #f5c6c2;
           border-radius: 8px; padding: 10px 12px; font-size: 13px; }
  .success { text-align: center; }
  .success .tick { font-size: 48px; }
  .back { display: inline-block; margin-top: 18px; color: #0F4C81; font-size: 14px; }
</style>
</head><body><div class="card">`;

    if (s.status === 'PAID') {
      const back = returnUrl
        ? `<a class="back" href="${escapeHtml(returnUrl)}">Return to ${merchantName}</a>`
        : '';
      return `${head}
  <div class="success">
    <div class="tick">✅</div>
    <div class="merchant">Payment complete</div>
    <div class="amount">${amount}</div>
    <div class="desc">paid to ${merchantName}${description ? ` — ${description}` : ''}</div>
    ${back}
  </div>
</div></body></html>`;
    }

    if (s.status === 'EXPIRED') {
      return `${head}
  <div class="success">
    <div class="tick">⏰</div>
    <div class="merchant">This checkout has expired</div>
    <div class="desc">Please return to ${merchantName} and start a new payment.</div>
  </div>
</div></body></html>`;
    }

    const qr = await this.qrDataUri(s.id);
    const expiresAtIso = s.expiresAt.toISOString();
    const returnUrlJson = JSON.stringify(returnUrl ?? '');
    return `${head}
  <div class="brand">MiniPay Checkout</div>
  <div class="merchant">${merchantName}</div>
  ${description ? `<div class="desc">${description}</div>` : ''}
  <div class="amount">${amount}</div>
  <div class="expiry">Expires in <span id="countdown">…</span></div>
  <hr class="divider">
  <h3>Pay with the MiniPay app</h3>
  <img class="qr" src="${qr}" alt="Scan to pay ${amount} to ${merchantName} with MiniPay" width="240" height="240">
  <div class="qr-hint">Scan with the MiniPay app, then confirm with your PIN</div>
  <hr class="divider">
  <h3>Or pay with your MiniPay account</h3>
  <form id="payform">
    <label for="email">MiniPay email</label>
    <input id="email" name="email" type="email" autocomplete="email" required>
    <label for="pin">6-digit payment PIN</label>
    <input id="pin" name="pin" type="password" inputmode="numeric" maxlength="6" autocomplete="off" required>
    <button type="submit" id="paybtn">Pay ${amount}</button>
    <div class="error" id="error"></div>
  </form>
<script>
(function () {
  var expiresAt = new Date(${JSON.stringify(expiresAtIso)}).getTime();
  var el = document.getElementById('countdown');
  function tick() {
    var left = Math.max(0, Math.floor((expiresAt - Date.now()) / 1000));
    var m = Math.floor(left / 60), s = left % 60;
    el.textContent = m + ':' + (s < 10 ? '0' : '') + s;
    if (left <= 0) setTimeout(function () { location.reload(); }, 1000);
  }
  tick(); setInterval(tick, 1000);

  var form = document.getElementById('payform');
  var btn = document.getElementById('paybtn');
  var err = document.getElementById('error');
  var returnUrl = ${returnUrlJson};
  var AMOUNT_LABEL = ${JSON.stringify(`Pay ${amount}`)};
  form.addEventListener('submit', function (e) {
    e.preventDefault();
    err.style.display = 'none';
    btn.disabled = true; btn.textContent = 'Paying…';
    fetch('/checkout/${id}/pay-web', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: document.getElementById('email').value.trim(),
        pin: document.getElementById('pin').value
      })
    }).then(function (r) { return r.json().then(function (b) { return { status: r.status, body: b }; }); })
      .then(function (res) {
        if (res.status >= 200 && res.status < 300) {
          location.href = location.pathname + (returnUrl ? '?returnUrl=' + encodeURIComponent(returnUrl) : '');
        } else {
          err.textContent = (res.body && res.body.message) || 'Payment failed — please try again.';
          err.style.display = 'block';
          btn.disabled = false; btn.textContent = AMOUNT_LABEL;
        }
      })
      .catch(function () {
        err.textContent = 'Network error — please try again.';
        err.style.display = 'block';
        btn.disabled = false; btn.textContent = AMOUNT_LABEL;
      });
  });
})();
</script>
</div></body></html>`;
  }
}
