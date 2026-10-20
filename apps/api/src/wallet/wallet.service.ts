import { BadRequestException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { LedgerAccountKind, TransactionStatus, TransactionType } from '@prisma/client';
import Stripe from 'stripe';
import { PrismaService } from '../prisma/prisma.service';
import { LedgerService } from '../ledger/ledger.service';
import { STRIPE_CLIENT } from '../stripe/stripe.provider';

export const MIN_DEPOSIT = 100n; // SGD 1.00 in minor units
export const MAX_DEPOSIT = 500000n; // SGD 5,000.00

/** Test-mode payment methods mapped from the mobile "test card" buttons. */
export const TEST_PAYMENT_METHODS: Record<string, string> = {
  visa: 'pm_card_visa',
  visa_debit: 'pm_card_visa_debit',
  mastercard: 'pm_card_mastercard',
};

@Injectable()
export class WalletService {
  constructor(
    private prisma: PrismaService,
    private ledger: LedgerService,
    @Inject(STRIPE_CLIENT) private stripe: Stripe,
  ) {}

  /** Get (or lazily create) the user's SGD wallet. */
  async ensureWallet(userId: string) {
    let wallet = await this.prisma.ledgerAccount.findFirst({
      where: { ownerId: userId, kind: LedgerAccountKind.WALLET, currency: 'SGD' },
    });
    if (!wallet) {
      wallet = await this.prisma.ledgerAccount.create({
        data: { ownerId: userId, kind: LedgerAccountKind.WALLET, currency: 'SGD' },
      });
    }
    return wallet;
  }

  async ensureTreasury() {
    let treasury = await this.prisma.ledgerAccount.findFirst({
      where: { kind: LedgerAccountKind.TREASURY, currency: 'SGD' },
    });
    if (!treasury) {
      treasury = await this.prisma.ledgerAccount.create({
        data: { kind: LedgerAccountKind.TREASURY, currency: 'SGD' },
      });
    }
    return treasury;
  }

  async getWalletSummary(userId: string) {
    const wallet = await this.ensureWallet(userId);
    const balance = await this.ledger.balance(wallet.id);
    const recent = await this.prisma.transaction.findMany({
      where: {
        OR: [{ fromAccountId: wallet.id }, { toAccountId: wallet.id }],
      },
      orderBy: { createdAt: 'desc' },
      take: 10, // home shows a short preview; full list is in History
    });
    return {
      walletId: wallet.id,
      balance: balance.toString(),
      currency: 'SGD',
      recent: recent.map((t) => ({
        id: t.id,
        type: t.type,
        status: t.status,
        amount: t.amount.toString(),
        currency: t.currency,
        direction: t.toAccountId === wallet.id ? 'IN' : 'OUT',
        createdAt: t.createdAt,
        completedAt: t.completedAt,
      })),
    };
  }

  /**
   * Start a deposit: PENDING transaction + Stripe PaymentIntent.
   * The wallet is credited ONLY by the webhook when Stripe reports success.
   */
  async createDepositIntent(userId: string, amount: bigint) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { status: true },
    });
    if (user?.status === 'FROZEN') {
      throw new ForbiddenException(
        'Your account is frozen. You cannot top up — contact support for help.',
      );
    }
    if (amount < MIN_DEPOSIT || amount > MAX_DEPOSIT) {
      throw new BadRequestException(
        `Deposit must be between SGD ${Number(MIN_DEPOSIT) / 100} and SGD ${Number(MAX_DEPOSIT) / 100}`,
      );
    }
    const wallet = await this.ensureWallet(userId);

    const paymentIntent = await this.stripe.paymentIntents.create({
      amount: Number(amount),
      currency: 'sgd',
      automatic_payment_methods: { enabled: true },
      metadata: { kind: 'DEPOSIT', userId },
    });

    const tx = await this.prisma.transaction.create({
      data: {
        type: TransactionType.DEPOSIT,
        status: TransactionStatus.PENDING,
        amount,
        currency: 'SGD',
        toAccountId: wallet.id,
        stripePaymentIntentId: paymentIntent.id,
      },
    });
    return {
      transactionId: tx.id,
      paymentIntentId: paymentIntent.id,
      amount: amount.toString(),
      currency: 'SGD',
    };
  }

  /**
   * TEST-MODE ONLY: confirm the PaymentIntent server-side with a Stripe test
   * payment method (simulates the user paying with a real card). Production
   * apps confirm client-side via Stripe PaymentSheet.
   */
  async confirmTestDeposit(userId: string, transactionId: string, card: string) {
    const pm = TEST_PAYMENT_METHODS[card];
    if (!pm) throw new BadRequestException('Unknown test card');

    const tx = await this.prisma.transaction.findUnique({ where: { id: transactionId } });
    if (!tx || tx.type !== TransactionType.DEPOSIT) throw new NotFoundException('Deposit not found');
    if (tx.status !== TransactionStatus.PENDING) {
      throw new BadRequestException(`Deposit is already ${tx.status}`);
    }
    const wallet = await this.ensureWallet(userId);
    if (tx.toAccountId !== wallet.id) throw new NotFoundException('Deposit not found');
    if (!tx.stripePaymentIntentId) throw new BadRequestException('Deposit has no PaymentIntent');

    await this.stripe.paymentIntents.confirm(tx.stripePaymentIntentId, {
      payment_method: pm,
      return_url: 'http://localhost:3000/payments/test-return',
    });
    // In test mode the confirm call resolves to succeeded synchronously;
    // the webhook is still the single writer that credits the wallet.
    return { ok: true, transactionId };
  }

  async getTransactionStatus(userId: string, transactionId: string) {
    const wallet = await this.ensureWallet(userId);
    const tx = await this.prisma.transaction.findUnique({ where: { id: transactionId } });
    if (!tx) throw new NotFoundException('Transaction not found');
    if (tx.fromAccountId !== wallet.id && tx.toAccountId !== wallet.id) {
      throw new NotFoundException('Transaction not found');
    }

    // Resolve counterparty names (same resolution as history).
    const accountIds = [tx.fromAccountId, tx.toAccountId].filter(
      (x): x is string => !!x,
    );
    const accounts = await this.prisma.ledgerAccount.findMany({
      where: { id: { in: accountIds } },
      select: {
        id: true,
        kind: true,
        owner: { select: { displayName: true } },
        merchant: { select: { name: true } },
      },
    });
    const nameOf = (accountId?: string | null) => {
      if (!accountId) return null;
      const a = accounts.find((x) => x.id === accountId);
      if (!a) return null;
      return a.merchant?.name ?? a.owner?.displayName ?? a.kind;
    };
    const isIn = tx.toAccountId === wallet.id;

    return {
      id: tx.id,
      transactionId: tx.id,
      type: tx.type,
      status: tx.status,
      amount: tx.amount.toString(),
      currency: tx.currency,
      direction: isIn ? 'IN' : 'OUT',
      counterparty: nameOf(isIn ? tx.fromAccountId : tx.toAccountId),
      createdAt: tx.createdAt,
      completedAt: tx.completedAt,
    };
  }

  /**
   * Paginated history with optional filters (PGW-7).
   * type: DEPOSIT | TRANSFER | MERCHANT_PAYMENT | REQUEST_PAYMENT
   * year/month: filter to that calendar month.
   */
  async getHistory(
    userId: string,
    opts: {
      type?: string;
      year?: number;
      month?: number;
      q?: string;
      skip: number;
      take: number;
    },
  ) {
    const wallet = await this.ensureWallet(userId);
    const where: any = {
      OR: [{ fromAccountId: wallet.id }, { toAccountId: wallet.id }],
    };
    if (opts.type && opts.type !== 'ALL') where.type = opts.type;
    if (opts.year && opts.month) {
      const start = new Date(Date.UTC(opts.year, opts.month - 1, 1));
      const end = new Date(Date.UTC(opts.year, opts.month, 1));
      where.createdAt = { gte: start, lt: end };
    }
    const rows = await this.prisma.transaction.findMany({
      where,
      orderBy: { createdAt: 'desc' },
    });
    // Resolve counterparty names for transfers/requests.
    const accountIds = [
      ...new Set(
        rows
          .flatMap((t) => [t.fromAccountId, t.toAccountId])
          .filter((x): x is string => !!x),
      ),
    ];
    const accounts = await this.prisma.ledgerAccount.findMany({
      where: { id: { in: accountIds } },
      select: {
        id: true,
        kind: true,
        owner: { select: { displayName: true } },
        merchant: { select: { name: true } },
      },
    });
    const nameOf = (accountId?: string | null) => {
      if (!accountId) return null;
      const a = accounts.find((x) => x.id === accountId);
      if (!a) return null;
      return a.merchant?.name ?? a.owner?.displayName ?? a.kind;
    };
    // Search by counterparty name (case-insensitive) after resolving names.
    const q = opts.q?.trim().toLowerCase();
    const filtered = q
      ? rows.filter((t) => {
          const name = (nameOf(t.toAccountId === wallet.id ? t.fromAccountId : t.toAccountId) ?? '')
            .toLowerCase();
          return name.includes(q);
        })
      : rows;
    const items = filtered.slice(opts.skip, opts.skip + opts.take);
    return {
      total: filtered.length,
      items: items.map((t) => ({
        id: t.id,
        type: t.type,
        status: t.status,
        amount: t.amount.toString(),
        currency: t.currency,
        direction: t.toAccountId === wallet.id ? 'IN' : 'OUT',
        counterparty:
          nameOf(t.toAccountId === wallet.id ? t.fromAccountId : t.toAccountId) ??
          null,
        createdAt: t.createdAt,
      })),
    };
  }

  /** Monthly report (PGW-7): totals per type + daily in/out series for charts. */
  async getMonthlyReport(userId: string, year: number, month: number) {
    const wallet = await this.ensureWallet(userId);
    const start = new Date(Date.UTC(year, month - 1, 1));
    const end = new Date(Date.UTC(year, month, 1));
    const rows = await this.prisma.transaction.findMany({
      where: {
        OR: [{ fromAccountId: wallet.id }, { toAccountId: wallet.id }],
        createdAt: { gte: start, lt: end },
        status: 'COMPLETED',
      },
    });
    const byType: Record<string, { inflow: bigint; outflow: bigint }> = {};
    const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
    const daily: { day: number; inflow: bigint; outflow: bigint }[] = Array.from(
      { length: daysInMonth },
      (_, i) => ({ day: i + 1, inflow: 0n, outflow: 0n }),
    );
    for (const t of rows) {
      const isIn = t.toAccountId === wallet.id;
      const bucket = (byType[t.type] ??= { inflow: 0n, outflow: 0n });
      if (isIn) bucket.inflow += t.amount;
      else bucket.outflow += t.amount;
      const day = new Date(t.createdAt).getUTCDate();
      if (isIn) daily[day - 1].inflow += t.amount;
      else daily[day - 1].outflow += t.amount;
    }
    const totals = {
      inflow: Object.values(byType).reduce((s, b) => s + b.inflow, 0n),
      outflow: Object.values(byType).reduce((s, b) => s + b.outflow, 0n),
    };
    const byTypeOut = Object.fromEntries(
      Object.entries(byType).map(([k, v]) => [
        k,
        { inflow: v.inflow.toString(), outflow: v.outflow.toString() },
      ]),
    );
    return {
      year,
      month,
      totals: {
        inflow: totals.inflow.toString(),
        outflow: totals.outflow.toString(),
        net: (totals.inflow - totals.outflow).toString(),
      },
      byType: byTypeOut,
      daily: daily.map((d) => ({
        day: d.day,
        inflow: d.inflow.toString(),
        outflow: d.outflow.toString(),
      })),
    };
  }

  /**
   * Webhook-driven deposit completion. Idempotent: the journal entry carries
   * an idempotency key derived from the PaymentIntent id.
   */
  async completeDeposit(paymentIntentId: string) {
    const tx = await this.prisma.transaction.findUnique({
      where: { stripePaymentIntentId: paymentIntentId },
    });
    if (!tx) return { handled: false, reason: 'unknown payment intent' };
    if (tx.status === TransactionStatus.COMPLETED) return { handled: true, alreadyCompleted: true };

    const walletId = tx.toAccountId;
    if (!walletId) return { handled: false, reason: 'no destination account' };

    // Belt & braces: if the account got frozen between paying and the webhook
    // arriving, do not credit — record it as failed instead.
    const owner = await this.prisma.ledgerAccount.findUnique({
      where: { id: walletId },
      select: { owner: { select: { status: true } } },
    });
    if (owner?.owner?.status === 'FROZEN') {
      await this.prisma.transaction.update({
        where: { id: tx.id },
        data: { status: TransactionStatus.FAILED, meta: { failReason: 'account frozen' } },
      });
      return { handled: true, rejected: 'account frozen' };
    }

    const treasury = await this.ensureTreasury();

    await this.ledger.post({
      type: 'DEPOSIT',
      description: `Deposit via Stripe (${paymentIntentId})`,
      transactionId: tx.id,
      idempotencyKey: `pi_${paymentIntentId}`,
      lines: [
        { accountId: treasury.id, direction: 'DEBIT', amount: tx.amount },
        { accountId: walletId, direction: 'CREDIT', amount: tx.amount },
      ],
    });

    await this.prisma.transaction.update({
      where: { id: tx.id },
      data: { status: TransactionStatus.COMPLETED, completedAt: new Date() },
    });
    return { handled: true };
  }

  async failDeposit(paymentIntentId: string, reason: string) {
    const tx = await this.prisma.transaction.findUnique({
      where: { stripePaymentIntentId: paymentIntentId },
    });
    if (!tx || tx.status !== TransactionStatus.PENDING) return { handled: false };
    await this.prisma.transaction.update({
      where: { id: tx.id },
      data: { status: TransactionStatus.FAILED, meta: { failReason: reason } },
    });
    return { handled: true };
  }
}
