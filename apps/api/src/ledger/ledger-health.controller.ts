import { Controller, Get, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { LedgerService } from './ledger.service';

/** Dev invariant checker: proves the ledger is balanced at any time. */
@Controller('ledger')
@UseGuards(JwtAuthGuard)
export class LedgerHealthController {
  constructor(private ledger: LedgerService) {}

  @Get('invariant')
  check() {
    return this.ledger.verifyInvariant();
  }
}
