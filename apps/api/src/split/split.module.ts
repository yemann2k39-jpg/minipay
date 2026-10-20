import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { RequestsModule } from '../requests/requests.module';
import { GeminiService } from './gemini.service';
import { SplitController } from './split.controller';
import { SplitService } from './split.service';

@Module({
  imports: [AuthModule, RequestsModule],
  controllers: [SplitController],
  providers: [SplitService, GeminiService],
})
export class SplitModule {}
