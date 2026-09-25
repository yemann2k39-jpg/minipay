import { Module } from '@nestjs/common';
import { TransfersService } from './transfers.service';
import { TransfersController } from './transfers.controller';
import { AuthModule } from '../auth/auth.module';
import { LedgerModule } from '../ledger/ledger.module';
import { ContactsModule } from '../contacts/contacts.module';

@Module({
  imports: [AuthModule, LedgerModule, ContactsModule],
  providers: [TransfersService],
  controllers: [TransfersController],
})
export class TransfersModule {}
