import { Controller, Get, Param, Res } from '@nestjs/common';
import type { Response } from 'express';
import { MerchantsService } from './merchants.service';

@Controller('merchants')
export class MerchantsController {
  constructor(private merchants: MerchantsService) {}

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
