import { BadRequestException } from '@nestjs/common';
import { computeShares } from './split-calculator';

describe('computeShares', () => {
  it('splits an item with no assignments equally among all participants', () => {
    const shares = computeShares({
      participants: ['a', 'b', 'c'],
      items: [{ name: 'Noodles', priceMinor: 900n, assignedUserIds: [] }],
      extraMinor: 0n,
    });
    expect(shares.get('a')).toBe(300n);
    expect(shares.get('b')).toBe(300n);
    expect(shares.get('c')).toBe(300n);
  });

  it('splits an item assigned to a subset among only the assignees', () => {
    const shares = computeShares({
      participants: ['a', 'b', 'c'],
      items: [{ name: 'Wine', priceMinor: 1000n, assignedUserIds: ['b', 'c'] }],
      extraMinor: 0n,
    });
    expect(shares.get('a')).toBe(0n);
    expect(shares.get('b')).toBe(500n);
    expect(shares.get('c')).toBe(500n);
  });

  it('splits the extra/tip equally among all participants', () => {
    const shares = computeShares({
      participants: ['a', 'b', 'c'],
      items: [{ name: 'Fries', priceMinor: 300n, assignedUserIds: [] }],
      extraMinor: 100n, // 100/3 -> 34/33/33
    });
    expect(shares.get('a')).toBe(100n + 34n);
    expect(shares.get('b')).toBe(100n + 33n);
    expect(shares.get('c')).toBe(100n + 33n);
  });

  it('distributes leftover cents by largest remainder with stable order (100/3 -> 34/33/33)', () => {
    const shares = computeShares({
      participants: ['a', 'b', 'c'],
      items: [{ name: 'Dish', priceMinor: 100n, assignedUserIds: [] }],
      extraMinor: 0n,
    });
    expect([...shares.values()]).toEqual([34n, 33n, 33n]);
  });

  it('gives the first two participants the extra cent when there are two leftovers (101/3 -> 34/34/33)', () => {
    const shares = computeShares({
      participants: ['a', 'b', 'c'],
      items: [{ name: 'Dish', priceMinor: 101n, assignedUserIds: [] }],
      extraMinor: 0n,
    });
    expect([...shares.values()]).toEqual([34n, 34n, 33n]);
  });

  it('orders remainder cents by participant order even when assignees come in a different order', () => {
    // Assignees listed as ['c', 'a'] must still be rounded in participant order a < c.
    const shares = computeShares({
      participants: ['a', 'b', 'c'],
      items: [{ name: 'Cake', priceMinor: 101n, assignedUserIds: ['c', 'a'] }],
      extraMinor: 0n,
    });
    expect(shares.get('a')).toBe(51n); // first in stable order gets the leftover cent
    expect(shares.get('c')).toBe(50n);
    expect(shares.get('b')).toBe(0n);
  });

  it('sums EXACTLY to item prices + extra across many items and participants', () => {
    const participants = ['p1', 'p2', 'p3', 'p4', 'p5'];
    const items = [
      { name: 'A', priceMinor: 999n, assignedUserIds: ['p1', 'p2'] },
      { name: 'B', priceMinor: 12345n, assignedUserIds: [] },
      { name: 'C', priceMinor: 7n, assignedUserIds: ['p3', 'p4', 'p5', 'p1'] },
      { name: 'D', priceMinor: 2500n, assignedUserIds: ['p5'] },
    ];
    const extraMinor = 333n;
    const shares = computeShares({ participants, items, extraMinor });

    const sum = [...shares.values()].reduce((acc, v) => acc + v, 0n);
    const expectedTotal = items.reduce((acc, i) => acc + i.priceMinor, 0n) + extraMinor;
    expect(sum).toBe(expectedTotal);
    expect(participants.every((p) => typeof shares.get(p) === 'bigint')).toBe(true);
  });

  it('ignores assignees that are not participants', () => {
    const shares = computeShares({
      participants: ['a', 'b'],
      items: [{ name: 'Soup', priceMinor: 200n, assignedUserIds: ['a', 'ghost-user'] }],
      extraMinor: 0n,
    });
    // 'ghost-user' dropped -> group is ['a'] -> a pays the whole item.
    expect(shares.get('a')).toBe(200n);
    expect(shares.get('b')).toBe(0n);
  });

  it('treats an item whose assignees are ALL non-participants as unassigned (split among all)', () => {
    const shares = computeShares({
      participants: ['a', 'b'],
      items: [{ name: 'Rice', priceMinor: 101n, assignedUserIds: ['ghost'] }],
      extraMinor: 0n,
    });
    expect(shares.get('a')).toBe(51n); // 101/2 -> first in stable order gets the extra cent
    expect(shares.get('b')).toBe(50n);
  });

  it('gives everything to the single participant', () => {
    const shares = computeShares({
      participants: ['solo'],
      items: [
        { name: 'X', priceMinor: 1999n, assignedUserIds: [] },
        { name: 'Y', priceMinor: 1n, assignedUserIds: ['solo'] },
      ],
      extraMinor: 55n,
    });
    expect(shares.get('solo')).toBe(2055n);
  });

  it('is deterministic for repeated calls', () => {
    const input = {
      participants: ['a', 'b', 'c'],
      items: [{ name: 'N', priceMinor: 1000n, assignedUserIds: ['a', 'b'] }],
      extraMinor: 7n,
    };
    const first = computeShares(input);
    const second = computeShares(input);
    expect([...first.entries()]).toEqual([...second.entries()]);
  });

  it('throws on empty participants', () => {
    expect(() =>
      computeShares({
        participants: [],
        items: [{ name: 'N', priceMinor: 100n, assignedUserIds: [] }],
        extraMinor: 0n,
      }),
    ).toThrow(BadRequestException);
  });

  it('throws on duplicate participants', () => {
    expect(() =>
      computeShares({
        participants: ['a', 'a', 'b'],
        items: [{ name: 'N', priceMinor: 100n, assignedUserIds: [] }],
        extraMinor: 0n,
      }),
    ).toThrow(BadRequestException);
  });

  it('throws on item price <= 0', () => {
    expect(() =>
      computeShares({
        participants: ['a', 'b'],
        items: [{ name: 'Freebie', priceMinor: 0n, assignedUserIds: [] }],
        extraMinor: 0n,
      }),
    ).toThrow(BadRequestException);
    expect(() =>
      computeShares({
        participants: ['a', 'b'],
        items: [{ name: 'Refund', priceMinor: -5n, assignedUserIds: [] }],
        extraMinor: 0n,
      }),
    ).toThrow(BadRequestException);
  });

  it('supports a negative extra (discount) with exact floor rounding and sum', () => {
    // 4500 items - 301 discount, 2 people: floor(-301/2) = -151, -150
    const shares = computeShares({
      participants: ['a', 'b'],
      items: [{ name: 'Bill', priceMinor: 4500n, assignedUserIds: [] }],
      extraMinor: -301n,
    });
    expect(shares.get('a')).toBe(2100n); // 2250 - 150 (stable order gets the +1)
    expect(shares.get('b')).toBe(2099n); // 2250 - 151
    const sum = [...shares.values()].reduce((s, v) => s + v, 0n);
    expect(sum).toBe(4500n - 301n);
  });

  it('handles a discount that zeroes out shares without crashing', () => {
    const shares = computeShares({
      participants: ['a', 'b'],
      items: [{ name: 'N', priceMinor: 100n, assignedUserIds: [] }],
      extraMinor: -100n, // full discount: everyone owes 0
    });
    expect(shares.get('a')).toBe(0n);
    expect(shares.get('b')).toBe(0n);
  });
});
