import { Injectable, NotFoundException } from '@nestjs/common';
import { LedgerAccountKind } from '@prisma/client';
import * as QRCode from 'qrcode';
import { PrismaService } from '../prisma/prisma.service';

/** Payload encoded in merchant QR codes. */
export function merchantQrPayload(code: string) {
  return `minipay://pay?merchant=${code}`;
}

@Injectable()
export class MerchantsService {
  constructor(private prisma: PrismaService) {}

  async findByCode(code: string) {
    const m = await this.prisma.merchant.findUnique({
      where: { code },
      include: { ledgerAccount: { select: { id: true } } },
    });
    if (!m || m.status !== 'ACTIVE') throw new NotFoundException('Merchant not found');
    return m;
  }

  async publicInfo(code: string) {
    const m = await this.findByCode(code);
    return { code: m.code, name: m.name };
  }

  async qrPng(code: string): Promise<Buffer> {
    await this.findByCode(code); // 404 for unknown codes
    return QRCode.toBuffer(merchantQrPayload(code), {
      type: 'png',
      width: 512,
      margin: 2,
    });
  }

  /** Seed helper: create merchant + its ledger account if missing. */
  async ensureMerchant(code: string, name: string) {
    const existing = await this.prisma.merchant.findUnique({ where: { code } });
    if (existing) return existing;
    const account = await this.prisma.ledgerAccount.create({
      data: { kind: LedgerAccountKind.MERCHANT, currency: 'SGD' },
    });
    return this.prisma.merchant.create({
      data: { code, name, ledgerAccountId: account.id },
    });
  }
}
