import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Res,
  UseGuards,
} from '@nestjs/common';
import type { Response } from 'express';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { MerchantsService } from './merchants.service';

@Controller('merchants')
export class MerchantsController {
  constructor(private merchants: MerchantsService) {}

  /** Merchant-mode home (PGW-18): the shop owned by the logged-in user. */
  @Get('mine')
  @UseGuards(JwtAuthGuard)
  async mine(@CurrentUser('userId') userId: string) {
    return this.merchants.getOwnedMerchant(userId);
  }

  /** Merchant-mode insights (PGW-27). */
  @Get('mine/insights')
  @UseGuards(JwtAuthGuard)
  insights(@CurrentUser('userId') userId: string) {
    return this.merchants.getOwnedMerchantInsights(userId);
  }

  /** Merchant-mode collect payment (PGW-19): create a QR-payable session. */
  @Post('mine/collect')
  @UseGuards(JwtAuthGuard)
  async collect(
    @CurrentUser('userId') userId: string,
    @Body() body: { amountMinor?: number; description?: string },
  ) {
    if (typeof body?.amountMinor !== 'number') {
      throw new BadRequestException('amountMinor is required');
    }
    return this.merchants.createCollectSession(userId, {
      amountMinor: body.amountMinor,
      description: body.description,
    });
  }

  /** Merchant-mode full refund (PGW-20). */
  @Post('mine/sales/:id/refund')
  @UseGuards(JwtAuthGuard)
  async refund(
    @CurrentUser('userId') userId: string,
    @Param('id') checkoutId: string,
  ) {
    return this.merchants.refundSale(userId, checkoutId);
  }

  /** Merchant-mode API key status (PGW-21) — never returns the key. */
  @Get('mine/keys')
  @UseGuards(JwtAuthGuard)
  keyStatus(@CurrentUser('userId') userId: string) {
    return this.merchants.getOwnedMerchantKeyStatus(userId);
  }

  /** Merchant-mode: create the first API key (PGW-21). Returned ONCE. */
  @Post('mine/keys')
  @UseGuards(JwtAuthGuard)
  createKey(@CurrentUser('userId') userId: string) {
    return this.merchants.createOwnedMerchantKey(userId);
  }

  /** Merchant-mode: rotate the API key (PGW-21). Returned ONCE. */
  @Post('mine/keys/rotate')
  @UseGuards(JwtAuthGuard)
  rotateKey(@CurrentUser('userId') userId: string) {
    return this.merchants.rotateOwnedMerchantKey(userId);
  }

  /** Merchant-mode payout (PGW-22): withdraw business balance to own wallet. */
  @Post('mine/withdraw')
  @UseGuards(JwtAuthGuard)
  async withdraw(
    @CurrentUser('userId') userId: string,
    @Body() body: { amountMinor?: number },
  ) {
    if (typeof body?.amountMinor !== 'number') {
      throw new BadRequestException('amountMinor is required');
    }
    return this.merchants.withdrawToWallet(userId, {
      amountMinor: body.amountMinor,
    });
  }

  /** Merchant-mode sales list (PGW-18/20): paged, searchable, sortable. */
  @Get('mine/sales')
  @UseGuards(JwtAuthGuard)
  async sales(
    @CurrentUser('userId') userId: string,
    @Query('q') q?: string,
    @Query('status') status?: string,
    @Query('sort') sort?: string,
    @Query('year') year?: string,
    @Query('month') month?: string,
    @Query('skip') skip?: string,
    @Query('take') take?: string,
  ) {
    return this.merchants.getOwnedMerchantSales(userId, {
      q,
      status,
      sort,
      year: year != null ? Number(year) : undefined,
      month: month != null ? Number(month) : undefined,
      skip: skip != null ? Number(skip) : undefined,
      take: take != null ? Number(take) : undefined,
    });
  }

  /** Public: merchant display info for the payment confirmation screen. */
  @Get(':code')
  info(@Param('code') code: string) {
    return this.merchants.publicInfo(code);
  }

  /** Public: the scannable QR code PNG (shown in a browser / print). */
  @Get(':code/qr.png')
  async qr(@Param('code') code: string, @Res() res: Response) {
    const png = await this.merchants.qrPng(code);
    res.type('image/png');
    res.send(png);
  }
}
