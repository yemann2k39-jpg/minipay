import { Module } from '@nestjs/common';
import { LedgerService } from './ledger.service';
import { LedgerHealthController } from './ledger-health.controller';

@Module({
  providers: [LedgerService],
  controllers: [LedgerHealthController],
  exports: [LedgerService],
})
export class LedgerModule {}
