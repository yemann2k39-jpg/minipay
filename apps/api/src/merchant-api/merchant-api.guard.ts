import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';
import type { Merchant } from '@prisma/client';
import { MerchantApiService } from './merchant-api.service';

export type RequestWithMerchant = Request & { merchant?: Merchant };

/** API-key auth for /merchant-api routes. Reads X-API-Key, resolves the
 *  Merchant by SHA-256 hash lookup and attaches it to `request.merchant`. */
@Injectable()
export class MerchantApiGuard implements CanActivate {
  constructor(private merchantApi: MerchantApiService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<RequestWithMerchant>();
    const headers = request.headers as Record<string, string | string[] | undefined>;
    const header = headers['x-api-key'];
    const apiKey = Array.isArray(header) ? header[0] : header;
    if (!apiKey) {
      throw new UnauthorizedException('Missing X-API-Key header');
    }
    const merchant = await this.merchantApi.findByApiKey(apiKey);
    if (!merchant) {
      throw new UnauthorizedException('Invalid API key');
    }
    request.merchant = merchant;
    return true;
  }
}
