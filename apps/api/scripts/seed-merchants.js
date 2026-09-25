// Seeds test merchants. Run: node scripts/seed-merchants.js
const { PrismaClient, LedgerAccountKind } = require('@prisma/client');
const prisma = new PrismaClient();

const MERCHANTS = [
  { code: 'MP-KOPI01', name: 'Kopi Tiam SG' },
  { code: 'MP-POPATO', name: 'Popato Snacks' },
  { code: 'MP-BOOKSG', name: 'Bedok Books' },
];

async function main() {
  for (const m of MERCHANTS) {
    const existing = await prisma.merchant.findUnique({ where: { code: m.code } });
    if (existing) {
      console.log(`merchant ${m.code} exists`);
      continue;
    }
    const account = await prisma.ledgerAccount.create({
      data: { kind: LedgerAccountKind.MERCHANT, currency: 'SGD' },
    });
    await prisma.merchant.create({
      data: { code: m.code, name: m.name, ledgerAccountId: account.id },
    });
    console.log(`created ${m.code} (${m.name})`);
  }
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
