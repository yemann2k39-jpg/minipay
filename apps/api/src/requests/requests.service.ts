import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { MoneyRequestStatus } from '@prisma/client';
import { AuthService } from '../auth/auth.service';
import { ContactsService } from '../contacts/contacts.service';
import { LedgerService } from '../ledger/ledger.service';
import { PrismaService } from '../prisma/prisma.service';

const MIN_AMOUNT = 100n;
const MAX_AMOUNT = 500000n;

@Injectable()
export class RequestsService {
  constructor(
    private prisma: PrismaService,
    private ledger: LedgerService,
    private auth: AuthService,
    private contacts: ContactsService,
  ) {}

  async create(requesterId: string, toEmail: string, amount: bigint, note?: string) {
    if (amount < MIN_AMOUNT || amount > MAX_AMOUNT) {
      throw new BadRequestException('Amount must be between SGD 1.00 and 5,000.00');
    }
    const payerUser = await this.contacts.resolveUser(toEmail);
    if (payerUser.id === requesterId) {
      throw new BadRequestException('You cannot request money from yourself');
    }
    const requester = await this.prisma.user.findUnique({ where: { id: requesterId } });

    const req = await this.prisma.moneyRequest.create({
      data: {
        requesterId,
        payerId: payerUser.id,
        amount,
        note: note?.trim() || null,
      },
    });

    await this.prisma.notification.create({
      data: {
        userId: payerUser.id,
        type: 'REQUEST_RECEIVED',
        title: 'Money request',
        body: `${requester!.displayName} requested SGD ${(Number(amount) / 100).toFixed(2)}.`,
      },
    });

    return {
      id: req.id,
      payer: { id: payerUser.id, displayName: payerUser.displayName },
      amount: amount.toString(),
      currency: 'SGD',
      note: req.note,
      status: req.status,
    };
  }

  async list(userId: string) {
    const all = await this.prisma.moneyRequest.findMany({
      where: {
        OR: [{ requesterId: userId }, { payerId: userId }],
      },
      orderBy: { createdAt: 'desc' },
      take: 50,
      include: {
        requester: { select: { id: true, displayName: true } },
        payer: { select: { id: true, displayName: true } },
      },
    });
    const toMe = [];
    const fromMe = [];
    for (const r of all) {
      const view = {
        id: r.id,
        amount: r.amount.toString(),
        currency: r.currency,
        note: r.note,
        status: r.status,
        createdAt: r.createdAt,
        counterparty:
          r.requesterId === userId ? r.payer.displayName : r.requester.displayName,
      };
      if (r.payerId === userId) toMe.push({ ...view, direction: 'IN' });
      else fromMe.push({ ...view, direction: 'OUT' });
    }
    return { toMe, fromMe };
  }

  /** Payer approves and pays the request from their wallet. */
  async pay(payerId: string, requestId: string, pin: string) {
    const mr = await this.prisma.moneyRequest.findUnique({ where: { id: requestId } });
    if (!mr) throw new NotFoundException('Request not found');
    if (mr.payerId !== payerId) throw new ForbiddenException('Not your request');
    if (mr.status !== 'PENDING') {
      throw new BadRequestException(`Request is already ${mr.status}`);
    }

    await this.auth.verifyPin(payerId, pin);

    const payer = await this.prisma.user.findUnique({ where: { id: payerId } });
    const requester = await this.prisma.user.findUnique({
      where: { id: mr.requesterId },
    });

    const [fromWallet, toWallet] = await Promise.all([
      this.prisma.ledgerAccount.findFirst({
        where: { ownerId: payerId, kind: 'WALLET', currency: 'SGD' },
      }),
      this.prisma.ledgerAccount.findFirst({
        where: { ownerId: mr.requesterId, kind: 'WALLET', currency: 'SGD' },
      }),
    ]);
    const ensuredTo =
      toWallet ??
      (await this.prisma.ledgerAccount.create({
        data: { ownerId: mr.requesterId, kind: 'WALLET', currency: 'SGD' },
      }));
    if (!fromWallet) throw new BadRequestException('Wallet not found');

    const tx = await this.prisma.transaction.create({
      data: {
        type: 'REQUEST_PAYMENT',
        status: 'PENDING',
        amount: mr.amount,
        currency: 'SGD',
        fromAccountId: fromWallet.id,
        toAccountId: ensuredTo.id,
      },
    });

    try {
      await this.ledger.post({
        type: 'REQUEST_PAYMENT',
        description: `Paid request from ${requester!.displayName}`,
        transactionId: tx.id,
        idempotencyKey: `tx_${tx.id}`,
        lines: [
          { accountId: fromWallet.id, direction: 'DEBIT', amount: mr.amount },
          { accountId: ensuredTo.id, direction: 'CREDIT', amount: mr.amount },
        ],
      });
    } catch (err) {
      await this.prisma.transaction.update({
        where: { id: tx.id },
        data: { status: 'FAILED' },
      });
      throw err;
    }

    await this.prisma.transaction.update({
      where: { id: tx.id },
      data: { status: 'COMPLETED', completedAt: new Date() },
    });
    await this.prisma.moneyRequest.update({
      where: { id: mr.id },
      data: { status: 'PAID', transactionId: tx.id, completedAt: new Date() },
    });

    const dollars = (Number(mr.amount) / 100).toFixed(2);
    await this.prisma.notification.createMany({
      data: [
        {
          userId: payerId,
          type: 'REQUEST_PAID',
          title: 'Request paid',
          body: `You paid SGD ${dollars} to ${requester!.displayName}.`,
        },
        {
          userId: mr.requesterId,
          type: 'REQUEST_PAID',
          title: 'Money received',
          body: `${payer!.displayName} paid your SGD ${dollars} request.`,
        },
      ],
    });

    return { id: mr.id, status: 'PAID', amount: mr.amount.toString() };
  }

  async decline(payerId: string, requestId: string) {
    const mr = await this.prisma.moneyRequest.findUnique({ where: { id: requestId } });
    if (!mr) throw new NotFoundException('Request not found');
    if (mr.payerId !== payerId) throw new ForbiddenException('Not your request');
    if (mr.status !== 'PENDING') {
      throw new BadRequestException(`Request is already ${mr.status}`);
    }
    await this.prisma.moneyRequest.update({
      where: { id: mr.id },
      data: { status: 'DECLINED' },
    });
    const payer = await this.prisma.user.findUnique({ where: { id: payerId } });
    await this.prisma.notification.create({
      data: {
        userId: mr.requesterId,
        type: 'REQUEST_DECLINED',
        title: 'Request declined',
        body: `${payer!.displayName} declined your SGD ${(Number(mr.amount) / 100).toFixed(2)} request.`,
      },
    });
    return { id: mr.id, status: 'DECLINED' };
  }

  async cancel(requesterId: string, requestId: string) {
    const mr = await this.prisma.moneyRequest.findUnique({ where: { id: requestId } });
    if (!mr) throw new NotFoundException('Request not found');
    if (mr.requesterId !== requesterId) throw new ForbiddenException('Not your request');
    if (mr.status !== 'PENDING') {
      throw new BadRequestException(`Request is already ${mr.status}`);
    }
    await this.prisma.moneyRequest.update({
      where: { id: mr.id },
      data: { status: 'CANCELLED' },
    });
    return { id: mr.id, status: 'CANCELLED' };
  }
}
