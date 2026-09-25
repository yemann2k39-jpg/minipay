import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Notification, TransactionStatus, TransactionType } from '@prisma/client';
import { AuthService } from '../auth/auth.service';
import { LedgerService } from '../ledger/ledger.service';
import { PrismaService } from '../prisma/prisma.service';

const MIN_TRANSFER = 100n; // SGD 1.00
const MAX_TRANSFER = 500000n; // SGD 5,000.00

@Injectable()
export class TransfersService {
  constructor(
    private prisma: PrismaService,
    private ledger: LedgerService,
    private auth: AuthService,
  ) {}

  private async walletOf(userId: string) {
    let wallet = await this.prisma.ledgerAccount.findFirst({
      where: { ownerId: userId, kind: 'WALLET', currency: 'SGD' },
    });
    if (!wallet) {
      // Recipients may never have deposited — create their wallet on demand.
      wallet = await this.prisma.ledgerAccount.create({
        data: { ownerId: userId, kind: 'WALLET', currency: 'SGD' },
      });
    }
    return wallet;
  }

  async transfer(
    userId: string,
    toUserId: string,
    amount: bigint,
    pin: string,
  ) {
    if (amount < MIN_TRANSFER || amount > MAX_TRANSFER) {
      throw new BadRequestException(
        'Amount must be between SGD 1.00 and 5,000.00',
      );
    }
    if (userId === toUserId) {
      throw new BadRequestException('You cannot send money to yourself');
    }

    const sender = await this.prisma.user.findUnique({ where: { id: userId } });
    if (sender?.status === 'FROZEN') {
      throw new ForbiddenException(
        'Your account is frozen. You cannot send money — contact support for help.',
      );
    }
    if (sender?.status !== 'ACTIVE') {
      throw new ForbiddenException('Account is not active');
    }
    const receiver = await this.prisma.user.findUnique({
      where: { id: toUserId },
    });
    // FROZEN users may still receive money; only closed accounts cannot.
    if (!receiver || receiver.status === 'CLOSED') {
      throw new NotFoundException('Recipient not found');
    }

    // PIN authorizes the money movement.
    await this.auth.verifyPin(userId, pin);

    const [fromWallet, toWallet] = await Promise.all([
      this.walletOf(userId),
      this.walletOf(toUserId),
    ]);

    const tx = await this.prisma.transaction.create({
      data: {
        type: TransactionType.TRANSFER,
        status: TransactionStatus.PENDING,
        amount,
        currency: 'SGD',
        fromAccountId: fromWallet.id,
        toAccountId: toWallet.id,
      },
    });

    try {
      await this.ledger.post({
        type: 'TRANSFER',
        description: `Transfer to ${receiver.displayName}`,
        transactionId: tx.id,
        idempotencyKey: `tx_${tx.id}`,
        lines: [
          { accountId: fromWallet.id, direction: 'DEBIT', amount },
          { accountId: toWallet.id, direction: 'CREDIT', amount },
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

    // In-app notifications for both sides.
    const dollars = Number(amount) / 100;
    await this.prisma.notification.createMany({
      data: [
        {
          userId,
          type: 'TRANSFER_SENT',
          title: 'Money sent',
          body: `You sent SGD ${dollars.toFixed(2)} to ${receiver.displayName}.`,
        },
        {
          userId: toUserId,
          type: 'TRANSFER_RECEIVED',
          title: 'Money received',
          body: `You received SGD ${dollars.toFixed(2)} from ${sender!.displayName}.`,
        },
      ],
    });

    return {
      transactionId: tx.id,
      to: { id: receiver.id, displayName: receiver.displayName },
      amount: amount.toString(),
      currency: 'SGD',
      status: 'COMPLETED',
    };
  }

  async unreadCount(userId: string) {
    const n = await this.prisma.notification.count({
      where: { userId, readAt: null },
    });
    return { count: n };
  }

  async listNotifications(userId: string) {
    const items: Notification[] = await this.prisma.notification.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    return items.map((n) => ({
      id: n.id,
      type: n.type,
      title: n.title,
      body: n.body,
      read: n.readAt != null,
      createdAt: n.createdAt,
    }));
  }

  async markRead(userId: string, id: string) {
    const n = await this.prisma.notification.findUnique({ where: { id } });
    if (!n || n.userId !== userId) throw new NotFoundException('Notification not found');
    await this.prisma.notification.update({
      where: { id },
      data: { readAt: new Date() },
    });
    return { success: true };
  }

  async markAllRead(userId: string) {
    await this.prisma.notification.updateMany({
      where: { userId, readAt: null },
      data: { readAt: new Date() },
    });
    return { success: true };
  }
}
