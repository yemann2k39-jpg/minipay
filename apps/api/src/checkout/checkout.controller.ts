import {
  Body,
  Controller,
  Get,
  GoneException,
  Header,
  HttpCode,
  NotFoundException,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { CheckoutService } from './checkout.service';
import { PayCheckoutDto, PayCheckoutWebDto } from './dto/pay-checkout.dto';
import { PrismaService } from '../prisma/prisma.service';

@Controller('checkout')
export class CheckoutController {
  constructor(
    private checkout: CheckoutService,
    private prisma: PrismaService,
  ) {}

  /** Customer (app) payment — JWT protected. */
  @Post(':id/pay')
  @HttpCode(200)
  @UseGuards(JwtAuthGuard)
  pay(
    @CurrentUser('userId') userId: string,
    @Param('id') id: string,
    @Body() dto: PayCheckoutDto,
  ) {
    return this.checkout.pay(userId, id, dto.pin);
  }

  /** Hosted-page email+PIN payment — public. */
  @Post(':id/pay-web')
  @HttpCode(200)
  payWeb(@Param('id') id: string, @Body() dto: PayCheckoutWebDto) {
    return this.checkout.payWeb(dto.email, id, dto.pin);
  }

  /** Public JSON status for the hosted page. */
  @Get(':id')
  async status(@Param('id') id: string) {
    const s = await this.checkout.getSessionOrExpire(id);
    if (s.status === 'EXPIRED') {
      throw new GoneException('This checkout has expired');
    }
    return this.checkout.publicStatus(id);
  }

  /** Public hosted checkout page (HTML, no-store). */
  @Get(':id/page')
  @Header('Content-Type', 'text/html; charset=utf-8')
  @Header('Cache-Control', 'no-store')
  async page(@Param('id') id: string, @Query('returnUrl') returnUrl?: string) {
    // Unknown id → 404 (before rendering).
    const exists = await this.prisma.checkoutSession.findUnique({ where: { id }, select: { id: true } });
    if (!exists) throw new NotFoundException('Checkout not found');
    return this.checkout.renderPage(id, returnUrl);
  }
}
