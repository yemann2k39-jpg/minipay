import {
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
}
