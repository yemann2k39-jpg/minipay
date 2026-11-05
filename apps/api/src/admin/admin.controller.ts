import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from './admin.guard';
import { AdminService } from './admin.service';

@Controller('admin')
@UseGuards(JwtAuthGuard, AdminGuard)
export class AdminController {
  constructor(private admin: AdminService) {}

  @Get('stats')
  stats() {
    return this.admin.stats();
  }

  @Get('users')
  users() {
    return this.admin.users();
  }

  @Post('users/:id/freeze')
  freeze(@Param('id') id: string) {
    return this.admin.setFrozen(id, true);
  }

  @Post('users/:id/unfreeze')
  unfreeze(@Param('id') id: string) {
    return this.admin.setFrozen(id, false);
  }

  @Get('transactions')
  transactions(@Query('take') take?: string) {
    return this.admin.transactions(Number(take ?? 50));
  }

  // --- MiniPay Checkout merchants -----------------------------------------

  @Post('merchants')
  createMerchant(@Body() body: { name: string; callbackUrl?: string }) {
    return this.admin.createMerchant(body?.name, body?.callbackUrl);
  }

  @Get('merchants')
  listMerchants() {
    return this.admin.listMerchants();
  }

  @Post('merchants/:id/rotate-key')
  rotateMerchantKey(@Param('id') id: string) {
    return this.admin.rotateMerchantKey(id);
  }

  @Post('merchants/:id/freeze')
  freezeMerchant(@Param('id') id: string) {
    return this.admin.setMerchantFrozen(id, true);
  }

  @Post('merchants/:id/unfreeze')
  unfreezeMerchant(@Param('id') id: string) {
    return this.admin.setMerchantFrozen(id, false);
  }
}
