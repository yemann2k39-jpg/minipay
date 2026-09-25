import { Module } from '@nestjs/common';
import { PaymentsController } from './payments.controller';
import { PaymentsService } from './payments.service';
import { WalletModule } from '../wallet/wallet.module';
import { MerchantsModule } from '../merchants/merchants.module';
import { AuthModule } from '../auth/auth.module';
import { LedgerModule } from '../ledger/ledger.module';
import { stripeClientProvider } from '../stripe/stripe.provider';

@Module({
  imports: [WalletModule, MerchantsModule, AuthModule, LedgerModule],
  providers: [PaymentsService, stripeClientProvider],
  controllers: [PaymentsController],
})
export class PaymentsModule {}
