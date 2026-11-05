import { Module } from '@nestjs/common';
import { AdminService } from './admin.service';
import { AdminController } from './admin.controller';
import { AdminGuard } from './admin.guard';
import { MerchantApiModule } from '../merchant-api/merchant-api.module';

@Module({
  imports: [MerchantApiModule],
  providers: [AdminService, AdminGuard],
  controllers: [AdminController],
})
export class AdminModule {}
