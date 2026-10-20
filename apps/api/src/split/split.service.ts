import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { MoneyRequest, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RequestsService } from '../requests/requests.service';
import { GeminiService } from './gemini.service';
import { computeShares } from './split-calculator';

type RequestStatus = MoneyRequest['status'];

const MIN_SHARE = 100n; // SGD 1.00 — every participant request must meet this
const MAX_SHARE = 500000n; // SGD 5,000.00

interface CreateSplitItemInput {
  name: string;
  priceMinor: number;
  assignedUserIds?: string[];
}

interface CreateSplitInput {
  title: string;
  participantUserIds: string[];
  items: CreateSplitItemInput[];
  extraMinor?: number;
  discountMinor?: number;
}

@Injectable()
export class SplitService {
  /** Per-user scan timestamps for a lightweight quota (#3 in review). */
  private scanTimestamps = new Map<string, number[]>();
  private static SCAN_LIMIT = 10;
  private static SCAN_WINDOW_MS = 5 * 60 * 1000;

  constructor(
    private prisma: PrismaService,
    private requests: RequestsService,
    private gemini: GeminiService,
  ) {}

  /** Scan a receipt photo via Gemini and return its items (minor units as strings). */
  async scan(userId: string, imageBase64: string, mimeType: string) {
    // Lightweight per-user quota: the scan endpoint proxies a paid external API.
    const now = Date.now();
    const stamps = (this.scanTimestamps.get(userId) ?? []).filter(
      (t) => now - t < SplitService.SCAN_WINDOW_MS,
    );
    if (stamps.length >= SplitService.SCAN_LIMIT) {
      throw new BadRequestException(
        'Too many receipt scans — try again in a few minutes',
      );
    }
    stamps.push(now);
    this.scanTimestamps.set(userId, stamps);

    const items = await this.gemini.scanReceipt(imageBase64, mimeType);
    return {
      items: items.map((i) => ({ name: i.name, priceMinor: i.priceMinor.toString() })),
    };
  }

  /**
   * Create a split session: validate, compute fair shares, then persist the
   * session + items + participants + one MoneyRequest per participant in a
   * single atomic transaction.
   */
  async create(creatorId: string, input: CreateSplitInput) {
    const title = input.title?.trim();
    if (!title) throw new BadRequestException('Give the split a title');

    const participants = input.participantUserIds ?? [];
    if (participants.length < 1) {
      throw new BadRequestException('Add at least one participant');
    }
    if (new Set(participants).size !== participants.length) {
      throw new BadRequestException('Participants must be unique');
    }
    if (participants.includes(creatorId)) {
      throw new BadRequestException(
        'You created this split — remove yourself from the participants',
      );
    }
    if (!Array.isArray(input.items) || input.items.length === 0) {
      throw new BadRequestException('Add at least one item from the receipt');
    }

    // Build BigInt items once; validate from the built form.
    const items = input.items.map((i) => ({
      name: i.name?.trim() ?? '',
      priceMinor: BigInt(i.priceMinor ?? 0),
      assignedUserIds: i.assignedUserIds ?? [],
    }));
    for (const item of items) {
      if (!item.name) throw new BadRequestException('Every item needs a name');
      if (item.priceMinor <= 0n || item.priceMinor > MAX_SHARE) {
        throw new BadRequestException(
          `Item "${item.name}" must cost between SGD 0.01 and 5,000.00`,
        );
      }
    }
    if (items.length > 100) {
      throw new BadRequestException('A split can have at most 100 items');
    }
    const extraMinor = BigInt(input.extraMinor ?? 0);
    const discountMinor = BigInt(input.discountMinor ?? 0);
    if (extraMinor < 0n || extraMinor > MAX_SHARE) {
      throw new BadRequestException('Extra must be between SGD 0.00 and 5,000.00');
    }
    if (discountMinor < 0n || discountMinor > MAX_SHARE) {
      throw new BadRequestException('Discount must be between SGD 0.00 and 5,000.00');
    }

    // Creator must be ACTIVE (frozen users cannot create splits), and every
    // participant a real ACTIVE/FROZEN MiniPay user (frozen can still be paid).
    const allIds = [creatorId, ...participants];
    const users = await this.prisma.user.findMany({
      where: { id: { in: allIds } },
      select: { id: true, displayName: true, status: true },
    });
    const userById = new Map(users.map((u) => [u.id, u]));
    const creator = userById.get(creatorId);
    if (!creator) throw new BadRequestException('Creator not found');
    if (creator.status === 'FROZEN') {
      throw new ForbiddenException(
        'Your account is frozen. You cannot create splits — contact support for help.',
      );
    }
    if (creator.status !== 'ACTIVE') {
      throw new ForbiddenException('Account is not active');
    }
    for (const pid of participants) {
      const u = userById.get(pid);
      if (!u || (u.status !== 'ACTIVE' && u.status !== 'FROZEN')) {
        throw new BadRequestException('One or more participants are not MiniPay users');
      }
    }
    const displayNameById = new Map(
      users.map((u) => [u.id, u.displayName] as const),
    );

    // The creator paid the bill, so they are a shareholder too — but no
    // request is ever raised against them. Requests are sent later, from the
    // detail page (sendRequests()).
    // Net adjustment = extra (tip) − discount. Total must stay >= 0.
    const netAdjustment = extraMinor - discountMinor;
    const itemsTotal = items.reduce((acc, i) => acc + i.priceMinor, 0n);
    if (itemsTotal + netAdjustment < 0n) {
      throw new BadRequestException(
        'The discount cannot exceed the bill total',
      );
    }
    const shares = computeShares({
      participants: [creatorId, ...participants],
      items,
      extraMinor: netAdjustment,
    });

    // SGD 1.00 minimum per request: refuse rather than mint under-minimum
    // requests or break the exact-sum invariant (applies to invited
    // participants only — the creator owes nothing).
    for (const pid of participants) {
      const share = shares.get(pid) ?? 0n;
      if (share < MIN_SHARE) {
        throw new BadRequestException(
          `A participant's share would be under SGD 1.00 — split between fewer people or increase the amount`,
        );
      }
      if (share > MAX_SHARE) {
        throw new BadRequestException(
          `A participant's share would be over SGD 5,000.00 — split between more people`,
        );
      }
    }

    const participantSet = new Set(participants);
    const session = await this.prisma.$transaction(async (tx) => {
      const shareholderIds = [creatorId, ...participants];
      return tx.splitSession.create({
        data: {
          creatorId,
          title,
          extraAmount: extraMinor,
          discountAmount: discountMinor,
          items: {
            create: items.map((i) => ({
              name: i.name,
              price: i.priceMinor,
              // Store only assignments that are actual participants.
              assignedUserIds: i.assignedUserIds.filter((id) =>
                participantSet.has(id),
              ),
            })),
          },
          participants: {
            create: shareholderIds.map((userId) => ({
              userId,
              shareAmount: shares.get(userId) ?? 0n,
            })),
          },
        },
        include: { items: true, participants: true },
      });
    });

    // NOTE: requests are NOT auto-created here. The creator sends them from
    // the detail page via sendRequests() (POST /split/:id/requests/send).

    return this.detail(creatorId, session.id);
  }

  /**
   * Send money requests to participants of a split. Creator only.
   * Targets participants with share > 0 that have no live request yet
   * (never sent, or the previous one was declined/cancelled).
   * Optionally limited to specific userIds.
   */
  async sendRequests(
    creatorId: string,
    sessionId: string,
    userIds?: string[],
  ) {
    const session = await this.prisma.splitSession.findUnique({
      where: { id: sessionId },
      include: {
        participants: {
          include: {
            user: { select: { displayName: true, status: true } },
            moneyRequest: { select: { status: true } },
          },
        },
      },
    });
    if (!session) throw new NotFoundException('Split not found');
    if (session.creatorId !== creatorId) {
      throw new ForbiddenException('Only the creator can send these requests');
    }

    const creator = await this.prisma.user.findUnique({
      where: { id: creatorId },
      select: { status: true },
    });
    if (creator?.status === 'FROZEN') {
      throw new ForbiddenException(
        'Your account is frozen. You cannot send requests — contact support for help.',
      );
    }

    const filter = new Set(userIds && userIds.length > 0 ? userIds : []);
    // Targets: invited, owe something, and have no LIVE request (never sent,
    // or the previous one was declined/cancelled — re-issue a fresh one).
    const targets = session.participants.filter(
      (p) =>
        p.userId !== creatorId && // the creator paid the bill
        p.shareAmount > 0n &&
        (p.moneyRequestId === null ||
          p.moneyRequest?.status === 'DECLINED' ||
          p.moneyRequest?.status === 'CANCELLED') &&
        (filter.size === 0 || filter.has(p.userId)) &&
        p.user.status !== 'CLOSED',
    );

    if (targets.length === 0) {
      return {
        sent: 0,
        alreadySent: true,
        message: 'All requests were already sent.',
      };
    }

    const sent: { userId: string; requestId: string }[] = [];
    for (const p of targets) {
      // Unlink the dead request (if any), then raise a fresh one.
      await this.prisma.splitParticipant.update({
        where: { id: p.id },
        data: { moneyRequestId: null },
      });
      const request = await this.requests.createInternal(
        creatorId,
        p.userId,
        p.shareAmount,
        `Split "${session.title}" — your share`,
        session.id,
      );
      await this.prisma.splitParticipant.update({
        where: { id: p.id },
        data: { moneyRequestId: request.id },
      });
      sent.push({ userId: p.userId, requestId: request.id });
    }
    return {
      sent: sent.length,
      requestIdByUser: Object.fromEntries(
        sent.map((s) => [s.userId, s.requestId]),
      ),
    };
  }

  /** Delete a split — only while no requests have been sent. */
  async delete(creatorId: string, sessionId: string) {
    const session = await this.prisma.splitSession.findUnique({
      where: { id: sessionId },
      include: { participants: true },
    });
    if (!session) throw new NotFoundException('Split not found');
    if (session.creatorId !== creatorId) {
      throw new ForbiddenException('Only the creator can delete this split');
    }
    const sent = session.participants.some((p) => p.moneyRequestId !== null);
    if (sent) {
      throw new BadRequestException(
        'Requests were already sent — this split can no longer be deleted',
      );
    }
    // Items and participants cascade with the session.
    await this.prisma.splitSession.delete({ where: { id: sessionId } });
    return { success: true };
  }

  /** Sessions I created, with per-participant request status and totals. */
  async list(userId: string) {
    const sessions = await this.prisma.splitSession.findMany({
      where: { creatorId: userId },
      orderBy: { createdAt: 'desc' },
      include: {
        items: true,
        participants: {
          include: {
            user: { select: { displayName: true } },
            moneyRequest: { select: { status: true } },
          },
        },
      },
    });
    return {
      sessions: sessions.map((s) => this.presentSession(s, userId)),
    };
  }

  /** Session detail with items and assignments (creator only). */
  async detail(userId: string, id: string) {
    const session = await this.prisma.splitSession.findUnique({
      where: { id },
      include: {
        items: true,
        participants: {
          include: {
            user: { select: { displayName: true } },
            moneyRequest: { select: { status: true } },
          },
        },
      },
    });
    if (!session) throw new NotFoundException('Split not found');
    if (session.creatorId !== userId) {
      throw new ForbiddenException('Only the creator can view this split');
    }
    return this.presentSession(session, userId);
  }

  // -------------------------------------------------------------------------

  private presentSession(
    session: {
      id: string;
      title: string;
      status: string;
      creatorId: string;
      extraAmount: bigint;
      discountAmount: bigint;
      createdAt: Date;
      items: { id: string; name: string; price: bigint; assignedUserIds: string[] }[];
      participants: {
        userId: string;
        shareAmount: bigint;
        moneyRequestId: string | null;
        user: { displayName: string };
        moneyRequest?: { status: RequestStatus } | null;
      }[];
    },
    viewerId: string,
  ) {
    const totalMinor =
      session.items.reduce((acc, i) => acc + i.price, 0n) +
      session.extraAmount -
      session.discountAmount;
    let paidMinor = 0n;
    let pendingMinor = 0n;
    const participants = session.participants.map((p) => {
      const isCreator = p.userId === session.creatorId;
      // The creator paid the bill up front — their row is informational.
      const status = isCreator ? 'PAID' : p.moneyRequest?.status ?? null;
      if (status === 'PAID') paidMinor += p.shareAmount;
      else if (status === 'PENDING') pendingMinor += p.shareAmount;
      return {
        userId: p.userId,
        displayName: p.user.displayName,
        shareAmount: p.shareAmount.toString(),
        requestId: p.moneyRequestId,
        isCreator,
        status,
      };
    });
    // A session is settled when every invited participant has paid (the
    // creator's share is already covered).
    const invited = participants.filter((p) => !p.isCreator);
    const allSettled =
      invited.length > 0 && invited.every((p) => p.status === 'PAID');
    return {
      id: session.id,
      title: session.title,
      status: allSettled ? 'SETTLED' : session.status,
      currency: 'SGD',
      createdAt: session.createdAt,
      extraMinor: session.extraAmount.toString(),
      discountMinor: session.discountAmount.toString(),
      totalMinor: totalMinor.toString(),
      paidMinor: paidMinor.toString(),
      pendingMinor: pendingMinor.toString(),
      items: session.items.map((i) => ({
        id: i.id,
        name: i.name,
        priceMinor: i.price.toString(),
        assignedUserIds: i.assignedUserIds,
      })),
      participants,
    };
  }
}
