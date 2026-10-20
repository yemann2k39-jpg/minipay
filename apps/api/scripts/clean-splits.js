// Clean smoke-test split sessions + their pending requests.
const { PrismaClient } = require('@prisma/client');
const p = new PrismaClient();
(async () => {
  const sessions = await p.splitSession.findMany({ select: { id: true } });
  for (const s of sessions) {
    await p.moneyRequest.deleteMany({ where: { splitSessionId: s.id, status: 'PENDING' } });
    await p.splitSession.delete({ where: { id: s.id } });
  }
  console.log('cleaned sessions:', sessions.length);
  await p.$disconnect();
})().catch((e) => { console.error(e.message); process.exit(1); });
