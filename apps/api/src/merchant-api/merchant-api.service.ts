import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { createHash, createHmac, randomBytes } from 'crypto';
import { LedgerAccountKind } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/** API key format: `mp_` + 32 hex chars (16 random bytes). */
export function generateApiKey(): string {
  return `mp_${randomBytes(16).toString('hex')}`;
}

export function hashApiKey(apiKey: string): string {
  return createHash('sha256').update(apiKey).digest('hex');
}

/** Merchant code generator for admin-created merchants. */
export function generateMerchantCode(): string {
  return `MP-${randomBytes(4).toString('hex').toUpperCase()}`;
}

export const CHECKOUT_TTL_MS = 15 * 60 * 1000; // sessions live 15 minutes

export interface CheckoutInput {
  orderRef: string;
  amountMinor: number;
  description?: string;
  callbackUrl?: string;
}

export interface ValidatedCheckout {
  orderRef: string;
  amountMinor: bigint;
  description?: string;
  callbackUrl?: string;
}

/**
 * Pure validation for POST /merchant-api/checkout. Returns a list of human
 * readable problems (empty = valid). Kept pure so it can be unit-tested
 * without a database.
 */
export function validateCheckoutInput(
  input: CheckoutInput,
  merchantDefaultCallbackUrl?: string | null,
): string[] {
  const problems: string[] = [];
  const orderRef = typeof input.orderRef === 'string' ? input.orderRef.trim() : '';
  if (!orderRef) problems.push('orderRef is required');
  else if (orderRef.length > 140) problems.push('orderRef must be at most 140 characters');

  const amount = input.amountMinor;
  if (!Number.isInteger(amount) || amount < 1 || amount > 5_000_000) {
    problems.push('amountMinor must be an integer between 1 and 5000000 (minor units)');
  }

  if (input.description != null) {
    if (typeof input.description !== 'string' || input.description.length > 280) {
      problems.push('description must be a string of at most 280 characters');
    }
  }

  if (input.callbackUrl != null) {
    if (
      typeof input.callbackUrl !== 'string' ||
      !/^https:\/\/.+/i.test(input.callbackUrl)
    ) {
      problems.push('callbackUrl must be an https:// URL');
    }
  } else if (!merchantDefaultCallbackUrl) {
    problems.push('callbackUrl is required (no default callback URL is set on the merchant)');
  }

  return problems;
}

/** Pure expiry check for checkout sessions. */
export function isSessionExpired(
  session: { status: string; expiresAt: Date },
  now: Date = new Date(),
): boolean {
  return session.status === 'PENDING' && session.expiresAt.getTime() < now.getTime();
}

/** Pure HMAC callback signature (hex HMAC-SHA256 of the raw body string). */
export function computeCallbackSignature(rawBody: string, apiKey: string): string {
  return createHmac('sha256', apiKey).update(rawBody).digest('hex');
}

@Injectable()
export class MerchantApiService {
  constructor(private prisma: PrismaService) {}

  /** Resolve a merchant from a plain API key (hash lookup). */
  async findByApiKey(apiKey: string) {
    if (!apiKey.startsWith('mp_')) return null;
    return this.prisma.merchant.findUnique({
      where: { apiKeyHash: hashApiKey(apiKey) },
    });
  }

  /** Admin: create a merchant + its settlement ledger account. Returns the API key ONCE. */
  async createMerchant(name: string, callbackUrl?: string) {
    if (!name?.trim()) throw new BadRequestException('name is required');
    const apiKey = generateApiKey();
    const account = await this.prisma.ledgerAccount.create({
      data: { kind: LedgerAccountKind.MERCHANT, currency: 'SGD' },
    });
    // Ensure a unique code even on (astronomically unlikely) collision.
    let merchant = null;
    for (let i = 0; i < 5 && !merchant; i++) {
      try {
        merchant = await this.prisma.merchant.create({
          data: {
            code: generateMerchantCode(),
            name: name.trim(),
            ledgerAccountId: account.id,
            apiKey,
            apiKeyHash: hashApiKey(apiKey),
            callbackUrl,
          },
        });
      } catch (e: any) {
        if (e?.code !== 'P2002') throw e;
      }
    }
    if (!merchant) throw new ConflictException('Could not generate a unique merchant code');
    return { merchant, apiKey };
  }

  /** Admin: rotate the API key. The new key is returned ONCE. */
  async rotateApiKey(merchantId: string) {
    const merchant = await this.prisma.merchant.findUnique({ where: { id: merchantId } });
    if (!merchant) throw new NotFoundException('Merchant not found');
    const apiKey = generateApiKey();
    const updated = await this.prisma.merchant.update({
      where: { id: merchantId },
      data: { apiKey, apiKeyHash: hashApiKey(apiKey) },
    });
    return { merchant: updated, apiKey };
  }

  /** Admin: list merchants (never returns keys). Includes settlement balance. */
  async listMerchants() {
    const merchants = await this.prisma.merchant.findMany({
      orderBy: { createdAt: 'desc' },
      include: {
        ledgerAccount: {
          select: { id: true, lines: { select: { direction: true, amount: true } } },
        },
        ownerUser: { select: { email: true, displayName: true, status: true } },
      },
    });
    return merchants.map((m) => {
      // MERCHANT is credit-positive (like WALLET) — balance = credits - debits.
      const balanceMinor = m.ledgerAccount.lines.reduce(
        (s, l) => s + (l.direction === 'CREDIT' ? l.amount : -l.amount),
        0n,
      );
      return {
        id: m.id,
        code: m.code,
        name: m.name,
        status: m.status,
        callbackUrl: m.callbackUrl,
        ledgerAccountId: m.ledgerAccount.id,
        balanceMinor: balanceMinor.toString(),
        owner: m.ownerUser
          ? { email: m.ownerUser.email, displayName: m.ownerUser.displayName, status: m.ownerUser.status }
          : null,
        createdAt: m.createdAt,
      };
    });
  }

  /** Admin: freeze/unfreeze a merchant. Frozen = no new checkouts, payouts or refunds. */
  async setMerchantFrozen(merchantId: string, frozen: boolean) {
    const merchant = await this.prisma.merchant.update({
      where: { id: merchantId },
      data: { status: frozen ? 'FROZEN' : 'ACTIVE' },
      include: { ownerUser: { select: { id: true } } },
    });
    if (merchant.ownerUser) {
      await this.prisma.notification.create({
        data: {
          userId: merchant.ownerUser.id,
          type: frozen ? 'ACCOUNT_FROZEN' : 'ACCOUNT_UNFROZEN',
          title: frozen ? 'Business account frozen' : 'Business account restored',
          body: frozen
            ? `${merchant.name} has been frozen. New checkout sessions, payouts and refunds are disabled. Existing sessions can still be paid. Contact support if you think this is a mistake.`
            : `${merchant.name} is active again. All features are available.`,
        },
      });
    }
    return { success: true };
  }
}
