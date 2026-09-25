const { PrismaClient } = require('@prisma/client');
const p = new PrismaClient();
p.user.findMany({ select: { email: true, status: true } })
  .then((u) => { console.log(JSON.stringify(u, null, 1)); return p.$disconnect(); })
  .catch((e) => { console.error(e); process.exit(1); });
