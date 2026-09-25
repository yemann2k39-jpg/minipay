import { Module } from '@nestjs/common';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { LedgerModule } from './ledger/ledger.module';
import { WalletModule } from './wallet/wallet.module';
import { PaymentsModule } from './payments/payments.module';
import { MerchantsModule } from './merchants/merchants.module';
import { ContactsModule } from './contacts/contacts.module';
import { TransfersModule } from './transfers/transfers.module';
import { RequestsModule } from './requests/requests.module';

@Module({
  imports: [
    PrismaModule,
    AuthModule,
    LedgerModule,
    WalletModule,
    PaymentsModule,
    MerchantsModule,
    ContactsModule,
    TransfersModule,
    RequestsModule,
  ],
})
export class AppModule {}
