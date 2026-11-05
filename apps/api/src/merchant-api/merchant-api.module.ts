import { Module } from '@nestjs/common';
import { PrismaModule } from '../prisma/prisma.module';
import { MerchantApiController } from './merchant-api.controller';
import { MerchantApiGuard } from './merchant-api.guard';
import { MerchantApiService } from './merchant-api.service';

@Module({
  imports: [PrismaModule],
  controllers: [MerchantApiController],
  providers: [MerchantApiService, MerchantApiGuard],
  exports: [MerchantApiService],
})
export class MerchantApiModule {}
