import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { TransactionStatus, TransactionType } from '@prisma/client';
import { AuthService } from '../auth/auth.service';
import { LedgerService } from '../ledger/ledger.service';
import { PrismaService } from '../prisma/prisma.service';
import { MerchantsService } from '../merchants/merchants.service';

const MIN_PAYMENT = 100n; // SGD 1.00
const MAX_PAYMENT = 500000n; // SGD 5,000.00

@Injectable()
export class PaymentsService {
  constructor(
    private prisma: PrismaService,
    private ledger: LedgerService,
    private merchants: MerchantsService,
    private auth: AuthService,
  ) {}

  /**
   * Merchant QR payment: user pays a merchant from their wallet.
   * Auth: JWT (who) + payment PIN (authorisation).
   * Atomic: single balanced journal entry (wallet -> merchant).
   */
  async payMerchant(userId: string, merchantCode: string, amount: bigint, pin: string) {
    if (amount < MIN_PAYMENT || amount > MAX_PAYMENT) {
      throw new BadRequestException('Amount must be between SGD 1.00 and 5,000.00');
    }

    const merchant = await this.merchants.findByCode(merchantCode);
    const merchantAccountId = merchant.ledgerAccountId;

    const wallet = await this.prisma.ledgerAccount.findFirst({
      where: { ownerId: userId, kind: 'WALLET', currency: 'SGD' },
    });
    if (!wallet) throw new NotFoundException('Wallet not found');

    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (user?.status === 'FROZEN') {
      throw new ForbiddenException(
        'Your account is frozen. You cannot make payments — contact support for help.',
      );
    }
    if (user?.status !== 'ACTIVE') throw new ForbiddenException('Account is not active');

    // Payment PIN authorises the money movement.
    await this.auth.verifyPin(userId, pin);

    const tx = await this.prisma.transaction.create({
      data: {
        type: TransactionType.MERCHANT_PAYMENT,
        status: TransactionStatus.PENDING,
        amount,
        currency: 'SGD',
        fromAccountId: wallet.id,
        toAccountId: merchantAccountId,
      },
    });

    try {
      await this.ledger.post({
        type: 'MERCHANT_PAYMENT',
        description: `Payment to ${merchant.name} (${merchant.code})`,
        transactionId: tx.id,
        idempotencyKey: `tx_${tx.id}`,
        lines: [
          { accountId: wallet.id, direction: 'DEBIT', amount },
          { accountId: merchantAccountId, direction: 'CREDIT', amount },
        ],
      });
    } catch (err) {
      await this.prisma.transaction.update({
        where: { id: tx.id },
        data: { status: TransactionStatus.FAILED },
      });
      throw err;
    }

    await this.prisma.transaction.update({
      where: { id: tx.id },
      data: { status: TransactionStatus.COMPLETED, completedAt: new Date() },
    });

    return {
      transactionId: tx.id,
      merchant: { code: merchant.code, name: merchant.name },
      amount: amount.toString(),
      currency: 'SGD',
      status: 'COMPLETED',
    };
  }
}
