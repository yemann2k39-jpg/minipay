import {
  BadRequestException,
  Injectable,
  InternalServerErrorException,
} from '@nestjs/common';
import { JournalDirection, JournalEntryType, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

export interface JournalLineInput {
  accountId: string;
  direction: JournalDirection;
  amount: bigint;
}

export interface PostJournalInput {
  type: JournalEntryType;
  description: string;
  transactionId?: string;
  /** Unique key so the same business event can never post twice. */
  idempotencyKey?: string;
  lines: JournalLineInput[];
}

export interface PostJournalResult {
  entryId: string;
  alreadyPosted: boolean;
}

/**
 * Double-entry ledger engine.
 *
 * Rules enforced here:
 *  1. Every journal entry balances: sum(debits) == sum(credits).
 *  2. User wallets may never go below zero.
 *  3. Posting is atomic: entry + all lines commit together, or nothing does.
 *  4. Posting takes an advisory lock per touched account so concurrent
 *     transfers of the same wallet serialize (no lost updates).
 *  5. idempotencyKey, when provided, makes re-submission a no-op.
 */
@Injectable()
export class LedgerService {
  constructor(private prisma: PrismaService) {}

  async post(input: PostJournalInput): Promise<PostJournalResult> {
    const { lines } = input;
    if (lines.length < 2) {
      throw new BadRequestException('A journal entry needs at least two lines');
    }
    const debits = lines
      .filter((l) => l.direction === 'DEBIT')
      .reduce((s, l) => s + l.amount, 0n);
    const credits = lines
      .filter((l) => l.direction === 'CREDIT')
      .reduce((s, l) => s + l.amount, 0n);
    if (debits !== credits) {
      throw new BadRequestException(
        `Unbalanced journal entry: debits ${debits} != credits ${credits}`,
      );
    }
    if (lines.some((l) => l.amount <= 0n)) {
      throw new BadRequestException('Journal line amounts must be positive');
    }

    return this.prisma.$transaction(
      async (tx) => {
        // Idempotency: if this exact business event already posted, return it.
        if (input.idempotencyKey) {
          const existing = await tx.journalEntry.findUnique({
            where: { idempotencyKey: input.idempotencyKey },
            select: { id: true },
          });
          if (existing) return { entryId: existing.id, alreadyPosted: true };
        }

        // Serialize posting per account. Advisory xact locks are cheap and
        // auto-released at commit/rollback. Sorting avoids deadlocks.
        const accountIds = [...new Set(lines.map((l) => l.accountId))].sort();
        for (const accountId of accountIds) {
          // Cast to text: the function returns void, which Prisma cannot deserialize.
          await tx.$queryRaw`SELECT CAST(pg_advisory_xact_lock(hashtext(${accountId})) AS TEXT)`;
        }

        // Verify the accounts exist (and are currency-consistent).
        const accounts = await tx.ledgerAccount.findMany({
          where: { id: { in: accountIds } },
          select: { id: true, currency: true, kind: true },
        });
        if (accounts.length !== accountIds.length) {
          throw new BadRequestException('Unknown ledger account');
        }
        for (const l of lines) {
          const acc = accounts.find((a) => a.id === l.accountId)!;
          if (acc.currency !== this.currencyOf(lines, l)) {
            throw new BadRequestException('Currency mismatch across journal lines');
          }
        }

        // Balance check per account, respecting its natural direction:
        //  - Assets  (TREASURY, FEES, CLEARING): debits increase → balance = debits - credits
        //  - Liability (WALLET): credits increase → balance = credits - debits
        // No account may go below zero in its natural direction.
        for (const accountId of accountIds) {
          const acc = accounts.find((a) => a.id === accountId)!;
          const isAsset = acc.kind !== 'WALLET';
          const [debitSum, creditSum] = await Promise.all([
            tx.journalLine.aggregate({
              where: { accountId, direction: 'DEBIT' },
              _sum: { amount: true },
            }),
            tx.journalLine.aggregate({
              where: { accountId, direction: 'CREDIT' },
              _sum: { amount: true },
            }),
          ]);
          const naturalBalance = isAsset
            ? (debitSum._sum.amount ?? 0n) - (creditSum._sum.amount ?? 0n)
            : (creditSum._sum.amount ?? 0n) - (debitSum._sum.amount ?? 0n);
          const delta = lines
            .filter((l) => l.accountId === accountId)
            .reduce(
              (s, l) =>
                s + (l.direction === 'DEBIT' ? l.amount : -l.amount),
              0n,
            );
          const signedDelta = isAsset ? delta : -delta;
          if (naturalBalance + signedDelta < 0n) {
            throw new BadRequestException(
              `Insufficient funds in ${acc.kind.toLowerCase()} account (balance ${naturalBalance})`,
            );
          }
        }

        const entry = await tx.journalEntry.create({
          data: {
            type: input.type,
            description: input.description,
            transactionId: input.transactionId,
            idempotencyKey: input.idempotencyKey,
            lines: {
              create: lines.map((l) => ({
                accountId: l.accountId,
                direction: l.direction,
                amount: l.amount,
              })),
            },
          },
          select: { id: true },
        });
        return { entryId: entry.id, alreadyPosted: false };
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted },
    );
  }

  private currencyOf(_lines: JournalLineInput[], _l: JournalLineInput): string {
    // Single-currency ledger (SGD) for now; kept as a seam for multi-currency.
    return 'SGD';
  }

  async balance(accountId: string): Promise<bigint> {
    const [credits, debits] = await Promise.all([
      this.prisma.journalLine.aggregate({
        where: { accountId, direction: 'CREDIT' },
        _sum: { amount: true },
      }),
      this.prisma.journalLine.aggregate({
        where: { accountId, direction: 'DEBIT' },
        _sum: { amount: true },
      }),
    ]);
    return (credits._sum.amount ?? 0n) - (debits._sum.amount ?? 0n);
  }

  /** Dev/debug invariant check: every wallet must have balance >= 0 and every entry balanced. */
  async verifyInvariant(): Promise<{ ok: boolean; problems: string[] }> {
    const problems: string[] = [];
    const accounts = await this.prisma.ledgerAccount.findMany({
      select: { id: true, kind: true },
    });
    for (const acc of accounts) {
      const b = await this.balance(acc.id);
      if (acc.kind === 'WALLET' && b < 0n) {
        problems.push(`wallet ${acc.id} negative: ${b}`);
      }
    }
    const entries = await this.prisma.journalEntry.findMany({
      select: { id: true, lines: { select: { direction: true, amount: true } } },
    });
    for (const e of entries) {
      const d = e.lines
        .filter((l) => l.direction === 'DEBIT')
        .reduce((s, l) => s + l.amount, 0n);
      const c = e.lines
        .filter((l) => l.direction === 'CREDIT')
        .reduce((s, l) => s + l.amount, 0n);
      if (d !== c) problems.push(`entry ${e.id} unbalanced`);
    }
    return { ok: problems.length === 0, problems };
  }
}
