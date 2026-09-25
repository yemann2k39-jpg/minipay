import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { WalletService } from './wallet.service';
import { ConfirmTestDepositDto, CreateDepositDto } from './wallet.dto';

@Controller('wallet')
@UseGuards(JwtAuthGuard)
export class WalletController {
  constructor(private wallet: WalletService) {}

  @Get()
  summary(@CurrentUser('userId') userId: string) {
    return this.wallet.getWalletSummary(userId);
  }

  @Post('deposits')
  createDeposit(@CurrentUser('userId') userId: string, @Body() dto: CreateDepositDto) {
    return this.wallet.createDepositIntent(userId, BigInt(dto.amount));
  }

  /** TEST-MODE ONLY — simulates paying with a real card. */
  @Post('deposits/:id/confirm-test')
  confirmTest(
    @CurrentUser('userId') userId: string,
    @Param('id') id: string,
    @Body() dto: ConfirmTestDepositDto,
  ) {
    return this.wallet.confirmTestDeposit(userId, id, dto.card);
  }

  @Get('transactions/:id')
  status(@CurrentUser('userId') userId: string, @Param('id') id: string) {
    return this.wallet.getTransactionStatus(userId, id);
  }
}
