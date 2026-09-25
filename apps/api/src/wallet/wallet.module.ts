import { Module } from '@nestjs/common';
import { WalletService } from './wallet.service';
import { WalletController } from './wallet.controller';
import { LedgerModule } from '../ledger/ledger.module';
import { stripeClientProvider } from '../stripe/stripe.provider';

@Module({
  imports: [LedgerModule],
  providers: [WalletService, stripeClientProvider],
  controllers: [WalletController],
  exports: [WalletService],
})
export class WalletModule {}
