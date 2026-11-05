import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  ForbiddenException,
  Get,
  NotFoundException,
  Param,
  Post,
  Res,
  UseGuards,
} from '@nestjs/common';
import { CheckoutSession } from '@prisma/client';
import type { Merchant } from '@prisma/client';
import type { Response } from 'express';
import { CurrentMerchant } from './current-merchant.decorator';
import { MerchantApiGuard } from './merchant-api.guard';
import { CHECKOUT_TTL_MS, isSessionExpired } from './merchant-api.service';
import { CreateCheckoutDto } from './dto/create-checkout.dto';
import { PrismaService } from '../prisma/prisma.service';

export function publicBaseUrl(): string {
  return process.env.PUBLIC_BASE_URL ?? 'http://localhost:3000';
}

export function checkoutUrl(id: string): string {
  return `${publicBaseUrl()}/checkout/${id}`;
}

function serializeSession(s: CheckoutSession) {
  return {
    checkoutId: s.id,
    orderRef: s.orderRef,
    status: s.status,
    amountMinor: s.amountMinor.toString(),
    currency: s.currency,
    expiresAt: s.expiresAt,
    ...(s.paidAt ? { paidAt: s.paidAt } : {}),
  };
}

@Controller('merchant-api')
@UseGuards(MerchantApiGuard)
export class MerchantApiController {
  constructor(private prisma: PrismaService) {}

  @Post('checkout')
  async createCheckout(
    @CurrentMerchant() merchant: Merchant,
    @Body() dto: CreateCheckoutDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    // FROZEN/CLOSED merchants cannot create new checkout sessions (PGW-17).
    // Existing PENDING sessions stay payable — frozen merchants can still receive.
    if (merchant.status !== 'ACTIVE') {
      throw new ForbiddenException(
        merchant.status === 'FROZEN'
          ? 'Merchant account is frozen — new checkouts are disabled'
          : 'Merchant account is closed',
      );
    }

    // Idempotency by (merchantId, orderRef).
    const existing = await this.prisma.checkoutSession.findUnique({
      where: { merchantId_orderRef: { merchantId: merchant.id, orderRef: dto.orderRef } },
    });
    if (existing && existing.status === 'PENDING') {
      // Idempotent create: return the still-pending session as 200.
      res.status(200);
      return { ...serializeSession(existing), checkoutUrl: checkoutUrl(existing.id) };
    }
    if (existing && existing.status === 'PAID') {
      throw new ConflictException(
        `orderRef "${dto.orderRef}" already has a PAID checkout session`,
      );
    }
    if (existing && existing.status === 'EXPIRED') {
      throw new ConflictException(
        `orderRef "${dto.orderRef}" was already used by an expired session — use a new orderRef`,
      );
    }

    const callbackUrl = dto.callbackUrl ?? merchant.callbackUrl;
    if (!callbackUrl) {
      throw new BadRequestException(
        'callbackUrl is required (no default callback URL is set on the merchant)',
      );
    }

    const session = await this.prisma.checkoutSession.create({
      data: {
        merchantId: merchant.id,
        orderRef: dto.orderRef,
        amountMinor: BigInt(dto.amountMinor),
        currency: 'SGD',
        description: dto.description,
        callbackUrl,
        expiresAt: new Date(Date.now() + CHECKOUT_TTL_MS),
      },
    });
    return { ...serializeSession(session), checkoutUrl: checkoutUrl(session.id) };
  }

  @Get('checkout/:id')
  async getCheckout(@CurrentMerchant() merchant: Merchant, @Param('id') id: string) {
    const session = await this.prisma.checkoutSession.findFirst({
      where: { id, merchantId: merchant.id },
    });
    if (!session) throw new NotFoundException('Checkout session not found');

    // Lazy expiry.
    if (isSessionExpired(session)) {
      const expired = await this.prisma.checkoutSession.update({
        where: { id: session.id },
        data: { status: 'EXPIRED' },
      });
      return serializeSession(expired);
    }
    return serializeSession(session);
  }
}
