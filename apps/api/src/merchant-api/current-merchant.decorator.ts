import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { Merchant } from '@prisma/client';
import type { RequestWithMerchant } from './merchant-api.guard';

/** The merchant resolved by MerchantApiGuard. */
export const CurrentMerchant = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): Merchant => {
    const request = ctx.switchToHttp().getRequest<RequestWithMerchant>();
    return request.merchant!;
  },
);
