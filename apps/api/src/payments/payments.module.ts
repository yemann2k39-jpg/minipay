import { Module } from '@nestjs/common';
import { PaymentsController } from './payments.controller';
import { WalletModule } from '../wallet/wallet.module';
import { stripeClientProvider } from '../stripe/stripe.provider';

@Module({
  imports: [WalletModule],
  providers: [stripeClientProvider],
  controllers: [PaymentsController],
})
export class PaymentsModule {}
