import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class AdminService {
  constructor(private prisma: PrismaService) {}

  async stats() {
    const [users, activeUsers, transactions] = await Promise.all([
      this.prisma.user.count(),
      this.prisma.user.count({ where: { status: 'ACTIVE' } }),
      this.prisma.transaction.count(),
    ]);
    const agg = await this.prisma.journalLine.aggregate({
      where: { direction: 'DEBIT', account: { kind: 'TREASURY' } },
      _sum: { amount: true },
    });
    return {
      users,
      activeUsers,
      transactions,
      volumeMinor: (agg._sum.amount ?? 0n).toString(),
    };
  }

  async users() {
    const wallets = await this.prisma.ledgerAccount.findMany({
      where: { kind: 'WALLET', currency: 'SGD' },
      select: {
        ownerId: true,
        lines: { select: { direction: true, amount: true } },
      },
    });
    const balanceByOwner = new Map<string, bigint>();
    for (const w of wallets) {
      if (!w.ownerId) continue;
      const bal = w.lines.reduce(
        (s, l) => s + (l.direction === 'CREDIT' ? l.amount : -l.amount),
        0n,
      );
      balanceByOwner.set(w.ownerId, (balanceByOwner.get(w.ownerId) ?? 0n) + bal);
    }
    const users = await this.prisma.user.findMany({
      select: {
        id: true,
        email: true,
        displayName: true,
        phone: true,
        role: true,
        status: true,
        createdAt: true,
      },
      orderBy: { createdAt: 'desc' },
    });
    return users.map((u) => ({
      ...u,
      balanceMinor: (balanceByOwner.get(u.id) ?? 0n).toString(),
    }));
  }

  async setFrozen(userId: string, frozen: boolean) {
    await this.prisma.user.update({
      where: { id: userId },
      data: { status: frozen ? 'FROZEN' : 'ACTIVE' },
    });
    await this.prisma.notification.create({
      data: {
        userId,
        type: frozen ? 'ACCOUNT_FROZEN' : 'ACCOUNT_UNFROZEN',
        title: frozen ? 'Account frozen' : 'Account restored',
        body: frozen
          ? 'Your account has been frozen. Sending, receiving and top-ups are disabled while frozen. Contact support if you think this is a mistake.'
          : 'Your account is active again. All features are available.',
      },
    });
    return { success: true };
  }

  async transactions(take: number) {
    const txs = await this.prisma.transaction.findMany({
      orderBy: { createdAt: 'desc' },
      take: Math.min(Math.max(take, 1), 200),
    });
    return txs.map((t) => ({
      ...t,
      amount: t.amount.toString(),
    }));
  }
}
