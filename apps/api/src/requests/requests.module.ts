import { Module } from '@nestjs/common';
import { RequestsService } from './requests.service';
import { RequestsController } from './requests.controller';
import { AuthModule } from '../auth/auth.module';
import { LedgerModule } from '../ledger/ledger.module';
import { ContactsModule } from '../contacts/contacts.module';

@Module({
  imports: [AuthModule, LedgerModule, ContactsModule],
  providers: [RequestsService],
  controllers: [RequestsController],
})
export class RequestsModule {}
