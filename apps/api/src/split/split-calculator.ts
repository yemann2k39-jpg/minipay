import { BadRequestException } from '@nestjs/common';

/**
 * Pure split-bill math. All amounts are integer minor units (cents).
 *
 * Rules (legacy-app behaviour, ported to BigInt):
 *  - An item with NO valid assignments is split equally among ALL participants.
 *  - An item with assignments is split equally among only those assignees
 *    (assignees that are not participants are ignored).
 *  - `extraMinor` (tip/extra) is always split equally among ALL participants.
 *    It may be NEGATIVE (a discount) — it then reduces everyone's share.
 *  - Fair rounding: largest-remainder method with FLOOR division (works for
 *    negative totals too). Everyone gets floor(share); leftover cents go
 *    one-by-one to the people with the largest fractional remainders — in an
 *    even split all fractional remainders are equal, so ties break by position
 *    in the `participants` array (stable order).
 *  - Exact-sum invariant: the shares of each split group sum to exactly the
 *    item price, and the grand total across participants equals
 *    sum(item prices) + extra.
 *  - Deterministic: same input always produces the same output.
 */

export interface SplitCalcItem {
  name: string;
  priceMinor: bigint;
  /** Empty/undefined = split among all participants. */
  assignedUserIds?: string[];
}

export interface SplitCalcInput {
  /** UserIds of the people who owe (excludes the creator). Order is the stable tie-break order. */
  participants: string[];
  items: SplitCalcItem[];
  /** Tip (positive) or discount (negative). Split equally among all. */
  extraMinor: bigint;
}

/** BigInt floor division (truncates toward -Infinity, not zero). */
function floorDiv(a: bigint, n: bigint): bigint {
  const q = a / n;
  const r = a % n;
  if (r !== 0n && r < 0n) return q - 1n;
  return q;
}

/**
 * Split `total` evenly among `group` with largest-remainder rounding.
 * Works for negative totals (discounts) via floor semantics.
 * `group` must be ordered by the stable participant order.
 */
function splitEven(total: bigint, group: string[]): Map<string, bigint> {
  const n = BigInt(group.length);
  const base = floorDiv(total, n);
  const leftover = Number(total - base * n); // 0..n-1 — safely small for Number
  const shares = new Map<string, bigint>();
  group.forEach((userId, idx) => {
    shares.set(userId, idx < leftover ? base + 1n : base);
  });
  return shares;
}

/**
 * Compute each participant's fair share of the bill.
 * Returns a map with an entry for every participant (0n if they owe nothing).
 * The values sum EXACTLY to sum(item prices) + extraMinor.
 */
export function computeShares(input: SplitCalcInput): Map<string, bigint> {
  const participants = input.participants;
  if (!Array.isArray(participants) || participants.length === 0) {
    throw new BadRequestException('A split needs at least one participant');
  }
  if (new Set(participants).size !== participants.length) {
    throw new BadRequestException('Participants must be unique');
  }
  const extra = input.extraMinor ?? 0n;
  if (typeof extra !== 'bigint') {
    throw new BadRequestException('Extra amount must be an integer');
  }
  const items = Array.isArray(input.items) ? input.items : [];
  for (const item of items) {
    if (typeof item.priceMinor !== 'bigint' || item.priceMinor <= 0n) {
      throw new BadRequestException(
        `Item "${item.name}" must have a price greater than zero`,
      );
    }
  }

  const position = new Map(participants.map((id, idx) => [id, idx]));
  const totals = new Map<string, bigint>(participants.map((id) => [id, 0n]));

  const addShares = (shares: Map<string, bigint>) => {
    for (const [userId, amount] of shares) {
      totals.set(userId, (totals.get(userId) ?? 0n) + amount);
    }
  };

  for (const item of items) {
    // Keep only assignees that are participants, drop duplicates, and order
    // them by their position in the participants array for stable rounding.
    const assignees = [...new Set(item.assignedUserIds ?? [])]
      .filter((id) => position.has(id))
      .sort((a, b) => position.get(a)! - position.get(b)!);
    const group = assignees.length > 0 ? assignees : participants;
    addShares(splitEven(item.priceMinor, group));
  }

  // Tip/extra is always split among everyone.
  addShares(splitEven(extra, participants));

  return totals;
}
