import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
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

  /** Paginated history with filters (PGW-7). */
  @Get('history')
  history(
    @CurrentUser('userId') userId: string,
    @Query('type') type?: string,
    @Query('year') year?: string,
    @Query('month') month?: string,
    @Query('q') q?: string,
    @Query('skip') skip?: string,
    @Query('take') take?: string,
  ) {
    return this.wallet.getHistory(userId, {
      type,
      year: year ? Number(year) : undefined,
      month: month ? Number(month) : undefined,
      q,
      skip: Number(skip ?? 0),
      take: Math.min(Number(take ?? 20), 50),
    });
  }

  /** Monthly report for charts (PGW-7). */
  @Get('report')
  report(
    @CurrentUser('userId') userId: string,
    @Query('year') year?: string,
    @Query('month') month?: string,
  ) {
    const now = new Date();
    return this.wallet.getMonthlyReport(
      userId,
      Number(year ?? now.getUTCFullYear()),
      Number(month ?? now.getUTCMonth() + 1),
    );
  }
}
