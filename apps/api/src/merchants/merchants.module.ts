import { Module } from '@nestjs/common';
import { LedgerModule } from '../ledger/ledger.module';
import { MerchantsService } from './merchants.service';
import { MerchantsController } from './merchants.controller';

@Module({
  imports: [LedgerModule],
  providers: [MerchantsService],
  controllers: [MerchantsController],
  exports: [MerchantsService],
})
export class MerchantsModule {}
