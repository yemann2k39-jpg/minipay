import { Injectable, NotFoundException, BadRequestException, ConflictException, ForbiddenException } from '@nestjs/common';
import { randomBytes } from 'crypto';
import { LedgerAccountKind, TransactionStatus, TransactionType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { LedgerService } from '../ledger/ledger.service';
import { generateApiKey, hashApiKey } from '../merchant-api/merchant-api.service';
import * as QRCode from 'qrcode';

/** Payload encoded in merchant QR codes. */
export function merchantQrPayload(code: string) {
  return `minipay://pay?merchant=${code}`;
}

@Injectable()
export class MerchantsService {
  constructor(
    private prisma: PrismaService,
    private ledger: LedgerService,
  ) {}

  /** Merchant-mode (PGW-18): the shop owned by this user, with balance. */
  async getOwnedMerchant(userId: string) {
    const m = await this.prisma.merchant.findFirst({
      where: { ownerUserId: userId },
      include: {
        ledgerAccount: {
          select: { lines: { select: { direction: true, amount: true } } },
        },
      },
    });
    if (!m) throw new NotFoundException('No merchant account linked to this user');
    // MERCHANT is credit-positive (like WALLET): credits - debits.
    const balanceMinor = m.ledgerAccount.lines.reduce(
      (s, l) => s + (l.direction === 'CREDIT' ? l.amount : -l.amount),
      0n,
    );
    return {
      id: m.id,
      code: m.code,
      name: m.name,
      status: m.status,
      balanceMinor: balanceMinor.toString(),
      createdAt: m.createdAt,
    };
  }

  /**
   * Merchant-mode (PGW-18/20): paged sales list with search, status filter
   * and sort — mirrors the wallet history contract ({items, total}).
   */
  async getOwnedMerchantSales(
    userId: string,
    opts: {
      q?: string;
      status?: string;
      sort?: string;
      year?: number;
      month?: number;
      skip?: number;
      take?: number;
    } = {},
  ) {
    const m = await this.prisma.merchant.findFirst({
      where: { ownerUserId: userId },
      select: { id: true },
    });
    if (!m) throw new NotFoundException('No merchant account linked to this user');

    const take = Math.min(Math.max(opts.take ?? 50, 1), 100);
    const skip = Math.max(opts.skip ?? 0, 0);
    const where: {
      merchantId: string;
      status?: string;
      OR?: object[];
      createdAt?: { gte?: Date; lt?: Date };
    } = { merchantId: m.id };
    if (opts.status && opts.status !== 'ALL') where.status = opts.status;
    if (opts.year != null && opts.month != null) {
      const start = new Date(Number(opts.year), Number(opts.month) - 1, 1);
      const end = new Date(Number(opts.year), Number(opts.month), 1);
      where.createdAt = { gte: start, lt: end };
    }
    if (opts.q?.trim()) {
      const q = opts.q.trim();
      where.OR = [
        { orderRef: { contains: q, mode: 'insensitive' } },
        { description: { contains: q, mode: 'insensitive' } },
      ];
    }
    const orderBy = (() => {
      switch (opts.sort) {
        case 'oldest':
          return [{ createdAt: 'asc' as const }];
        case 'amount_high':
          return [{ amountMinor: 'desc' as const }];
        case 'amount_low':
          return [{ amountMinor: 'asc' as const }];
        default:
          return [{ createdAt: 'desc' as const }];
      }
    })();

    const [total, sessions] = await Promise.all([
      this.prisma.checkoutSession.count({ where }),
      this.prisma.checkoutSession.findMany({
        where,
        orderBy,
        skip,
        take,
      }),
    ]);
    const items = sessions.map((s) => ({
      id: s.id,
      orderRef: s.orderRef,
      amountMinor: s.amountMinor.toString(),
      currency: s.currency,
      description: s.description,
      status: s.status,
      paidAt: s.paidAt,
      createdAt: s.createdAt,
    }));
    return { items, total };
  }

  async findByCode(code: string) {
    const m = await this.prisma.merchant.findUnique({
      where: { code },
      include: { ledgerAccount: { select: { id: true } } },
    });
    if (!m || m.status !== 'ACTIVE') throw new NotFoundException('Merchant not found');
    return m;
  }

  async publicInfo(code: string) {
    const m = await this.findByCode(code);
    return { code: m.code, name: m.name };
  }

  async qrPng(code: string): Promise<Buffer> {
    await this.findByCode(code); // 404 for unknown codes
    return QRCode.toBuffer(merchantQrPayload(code), {
      type: 'png',
      width: 512,
      margin: 2,
    });
  }

  /** Merchant-mode (PGW-19): create an in-person collect-payment session. */
  async createCollectSession(
    userId: string,
    input: { amountMinor: number; description?: string },
  ) {
    const m = await this.prisma.merchant.findFirst({
      where: { ownerUserId: userId },
      include: { ledgerAccount: { select: { id: true } } },
    });
    if (!m) throw new NotFoundException('No merchant account linked to this user');
    // FROZEN/CLOSED shops cannot create new payment requests.
    if (m.status !== 'ACTIVE') {
      throw new ForbiddenException(
        m.status === 'FROZEN'
          ? 'Your business account is frozen — payment requests are disabled'
          : 'Your business account is closed',
      );
    }
    const amount = input.amountMinor;
    if (!Number.isInteger(amount) || amount < 1 || amount > 5_000_000) {
      throw new BadRequestException(
        'amountMinor must be an integer between 1 and 5000000 (minor units)',
      );
    }
    if (input.description != null && input.description.length > 280) {
      throw new BadRequestException('description must be at most 280 characters');
    }
    // App-created sessions have no website to call back; keep the column
    // satisfied with a stable placeholder (never actually called).
    const callbackUrl = 'https://callbacks.minipay.invalid/app-collect';
    let session = null;
    for (let i = 0; i < 5 && !session; i++) {
      try {
        session = await this.prisma.checkoutSession.create({
          data: {
            merchantId: m.id,
            orderRef: `APP-${randomBytes(4).toString('hex').toUpperCase()}`,
            amountMinor: BigInt(amount),
            currency: 'SGD',
            description: input.description?.trim() || null,
            callbackUrl,
            expiresAt: new Date(Date.now() + 15 * 60 * 1000),
          },
        });
      } catch (e: any) {
        if (e?.code !== 'P2002') throw e;
      }
    }
    if (!session) throw new ConflictException('Could not generate a unique order reference');
    return {
      checkoutId: session.id,
      orderRef: session.orderRef,
      amountMinor: session.amountMinor.toString(),
      status: session.status,
      expiresAt: session.expiresAt,
      qrPayload: `minipay://checkout/${session.id}`,
    };
  }

  /**
   * Merchant-mode full refund (PGW-20): return a PAID checkout's amount to
   * the payer's wallet. Balanced REFUND journal entry with its own
   * idempotency key. Frozen merchants cannot refund. No partial refunds.
   */
  async refundSale(userId: string, checkoutId: string) {
    const m = await this.prisma.merchant.findFirst({
      where: { ownerUserId: userId },
      select: { id: true, name: true, status: true, ledgerAccountId: true },
    });
    if (!m) throw new NotFoundException('No merchant account linked to this user');
    if (m.status === 'FROZEN') {
      throw new ForbiddenException('Your business account is frozen — refunds are disabled');
    }
    if (m.status === 'CLOSED') {
      throw new ForbiddenException('Your business account is closed');
    }
    const session = await this.prisma.checkoutSession.findFirst({
      where: { id: checkoutId, merchantId: m.id },
    });
    if (!session) throw new NotFoundException('Sale not found');
    if (session.status === 'REFUNDED') {
      throw new ConflictException('This sale has already been refunded');
    }
    if (session.status !== 'PAID') {
      throw new BadRequestException('Only paid sales can be refunded');
    }
    if (!session.transactionId) {
      throw new ConflictException('This sale has no payment transaction to refund');
    }
    const payment = await this.prisma.transaction.findUnique({
      where: { id: session.transactionId },
      select: { fromAccountId: true },
    });
    if (!payment?.fromAccountId) {
      throw new ConflictException('Original payer wallet not found — cannot refund');
    }

    // Atomically claim PAID -> REFUNDED (guards concurrent refunds).
    const claim = await this.prisma.checkoutSession.updateMany({
      where: { id: session.id, status: 'PAID' },
      data: { status: 'REFUNDED' },
    });
    if (claim.count === 0) {
      throw new ConflictException('This sale has already been refunded');
    }

    const tx = await this.prisma.transaction.create({
      data: {
        type: TransactionType.REFUND,
        status: TransactionStatus.COMPLETED,
        amount: session.amountMinor,
        currency: session.currency,
        fromAccountId: m.ledgerAccountId,
        toAccountId: payment.fromAccountId,
        completedAt: new Date(),
        meta: { refundOfCheckoutId: session.id, orderRef: session.orderRef },
      },
    });

    try {
      await this.ledger.post({
        type: 'REFUND',
        description: `Refund ${session.orderRef} — ${m.name}`,
        transactionId: tx.id,
        idempotencyKey: `refund_${session.id}`,
        lines: [
          { accountId: m.ledgerAccountId, direction: 'DEBIT', amount: session.amountMinor },
          { accountId: payment.fromAccountId, direction: 'CREDIT', amount: session.amountMinor },
        ],
      });
    } catch (e) {
      // Roll the claim back so the sale stays refundable.
      await this.prisma.checkoutSession.updateMany({
        where: { id: session.id, status: 'REFUNDED' },
        data: { status: 'PAID' },
      });
      await this.prisma.transaction.delete({ where: { id: tx.id } }).catch(() => {});
      throw e;
    }
    return { success: true, status: 'REFUNDED', amountMinor: session.amountMinor.toString() };
  }

  /** Merchant-mode (PGW-21): key status — never returns the key itself. */
  async getOwnedMerchantKeyStatus(userId: string) {
    const m = await this.prisma.merchant.findFirst({
      where: { ownerUserId: userId },
      select: { status: true, apiKeyHash: true, callbackUrl: true },
    });
    if (!m) throw new NotFoundException('No merchant account linked to this user');
    return {
      hasKey: m.apiKeyHash != null,
      callbackUrl: m.callbackUrl,
      status: m.status,
    };
  }

  /** Merchant-mode (PGW-21): create the first API key. Returned ONCE. */
  async createOwnedMerchantKey(userId: string) {
    const m = await this.prisma.merchant.findFirst({
      where: { ownerUserId: userId },
      select: { id: true, status: true, apiKeyHash: true },
    });
    if (!m) throw new NotFoundException('No merchant account linked to this user');
    if (m.status === 'CLOSED') throw new ForbiddenException('Your business account is closed');
    if (m.apiKeyHash) {
      throw new ConflictException(
        'An API key already exists — rotate it to get a new one',
      );
    }
    const apiKey = generateApiKey();
    await this.prisma.merchant.update({
      where: { id: m.id },
      data: { apiKey, apiKeyHash: hashApiKey(apiKey) },
    });
    return { apiKey }; // shown once — only the SHA-256 hash is stored
  }

  /** Merchant-mode (PGW-21): rotate the API key (old key dies). Returned ONCE. */
  async rotateOwnedMerchantKey(userId: string) {
    const m = await this.prisma.merchant.findFirst({
      where: { ownerUserId: userId },
      select: { id: true, status: true },
    });
    if (!m) throw new NotFoundException('No merchant account linked to this user');
    if (m.status === 'CLOSED') throw new ForbiddenException('Your business account is closed');
    const apiKey = generateApiKey();
    await this.prisma.merchant.update({
      where: { id: m.id },
      data: { apiKey, apiKeyHash: hashApiKey(apiKey) },
    });
    return { apiKey }; // shown once
  }

  /**
   * Merchant-mode payout (PGW-22): move shop balance to the owner's wallet.
   * Balanced WITHDRAWAL journal entry with its own idempotency key.
   */
  async withdrawToWallet(userId: string, input: { amountMinor: number }) {
    const m = await this.prisma.merchant.findFirst({
      where: { ownerUserId: userId },
      select: { id: true, name: true, status: true, ledgerAccountId: true },
    });
    if (!m) throw new NotFoundException('No merchant account linked to this user');
    if (m.status === 'FROZEN') {
      throw new ForbiddenException('Your business account is frozen — withdrawals are disabled');
    }
    if (m.status === 'CLOSED') {
      throw new ForbiddenException('Your business account is closed');
    }
    const amount = input.amountMinor;
    if (!Number.isInteger(amount) || amount < 1) {
      throw new BadRequestException('amountMinor must be a positive integer (minor units)');
    }
    const balance = await this.ledger.balance(m.ledgerAccountId);
    if (balance < BigInt(amount)) {
      throw new BadRequestException(
        'Insufficient business balance for this withdrawal',
      );
    }
    // Owner wallet (the ledger creates it if this is their first payout).
    let wallet = await this.prisma.ledgerAccount.findFirst({
      where: { ownerId: userId, kind: LedgerAccountKind.WALLET, currency: 'SGD' },
    });
    if (!wallet) {
      wallet = await this.prisma.ledgerAccount.create({
        data: { ownerId: userId, kind: LedgerAccountKind.WALLET, currency: 'SGD' },
      });
    }
    const tx = await this.prisma.transaction.create({
      data: {
        type: TransactionType.TRANSFER,
        status: TransactionStatus.COMPLETED,
        amount: BigInt(amount),
        currency: 'SGD',
        fromAccountId: m.ledgerAccountId,
        toAccountId: wallet.id,
        completedAt: new Date(),
        meta: { withdrawal: true, merchantName: m.name },
      },
    });
    try {
      await this.ledger.post({
        type: 'WITHDRAWAL',
        description: `Withdraw to wallet — ${m.name}`,
        transactionId: tx.id,
        idempotencyKey: `withdraw_${tx.id}`,
        lines: [
          { accountId: m.ledgerAccountId, direction: 'DEBIT', amount: BigInt(amount) },
          { accountId: wallet.id, direction: 'CREDIT', amount: BigInt(amount) },
        ],
      });
    } catch (e) {
      await this.prisma.transaction.delete({ where: { id: tx.id } }).catch(() => {});
      throw e;
    }
    return {
      success: true,
      amountMinor: amount.toString(),
      walletBalanceMinor: (await this.ledger.balance(wallet.id)).toString(),
    };
  }

  /** Merchant-mode insights (PGW-27): today/week totals + 7-day buckets. */
  async getOwnedMerchantInsights(userId: string) {
    const m = await this.prisma.merchant.findFirst({
      where: { ownerUserId: userId },
      select: { id: true, name: true },
    });
    if (!m) throw new NotFoundException('No merchant account linked to this user');
    const now = new Date();
    const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const weekAgo = new Date(startOfToday.getTime() - 6 * 24 * 60 * 60 * 1000);
    // A sale is a checkout session that reached PAID (refunds included as
    // gross sales; refunded amounts reported separately).
    const recent = await this.prisma.checkoutSession.findMany({
      where: {
        merchantId: m.id,
        status: { in: ['PAID', 'REFUNDED'] },
        paidAt: { gte: weekAgo },
      },
      select: { amountMinor: true, status: true, paidAt: true },
    });
    const sum = (rows: { amountMinor: bigint }[]) =>
      rows.reduce((s, r) => s + r.amountMinor, 0n).toString();
    const today = recent.filter((r) => r.paidAt && r.paidAt >= startOfToday);
    const refundedWeek = recent.filter((r) => r.status === 'REFUNDED');
    // 7-day buckets, oldest first.
    const days: { date: string; totalMinor: string; count: number }[] = [];
    for (let i = 6; i >= 0; i--) {
      const dayStart = new Date(startOfToday.getTime() - i * 24 * 60 * 60 * 1000);
      const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);
      const rows = recent.filter(
        (r) => r.paidAt && r.paidAt >= dayStart && r.paidAt < dayEnd,
      );
      days.push({
        date: dayStart.toISOString().slice(0, 10),
        totalMinor: sum(rows),
        count: rows.length,
      });
    }
    return {
      todayTotalMinor: sum(today),
      todayCount: today.length,
      weekTotalMinor: sum(recent),
      weekCount: recent.length,
      refundedWeekMinor: sum(refundedWeek),
      days,
    };
  }

  /** Seed helper: create merchant + its ledger account if missing. */
  async ensureMerchant(code: string, name: string) {
    const existing = await this.prisma.merchant.findUnique({ where: { code } });
    if (existing) return existing;
    const account = await this.prisma.ledgerAccount.create({
      data: { kind: LedgerAccountKind.MERCHANT, currency: 'SGD' },
    });
    return this.prisma.merchant.create({
      data: { code, name, ledgerAccountId: account.id },
    });
  }
}
