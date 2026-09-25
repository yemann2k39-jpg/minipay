import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { IsEmail, IsInt, IsOptional, IsString, MaxLength } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { RequestsService } from './requests.service';

export class CreateRequestDto {
  @IsEmail()
  toEmail: string;

  @IsInt()
  amount: number; // minor units

  @IsOptional()
  @IsString()
  @MaxLength(140)
  note?: string;
}

export class PayRequestDto {
  @IsString()
  pin: string;
}

@Controller('requests')
@UseGuards(JwtAuthGuard)
export class RequestsController {
  constructor(private requests: RequestsService) {}

  @Post()
  create(
    @CurrentUser('userId') userId: string,
    @Body() dto: CreateRequestDto,
  ) {
    return this.requests.create(
      userId,
      dto.toEmail,
      BigInt(dto.amount),
      dto.note,
    );
  }

  @Get()
  list(@CurrentUser('userId') userId: string) {
    return this.requests.list(userId);
  }

  @Post(':id/pay')
  pay(
    @CurrentUser('userId') userId: string,
    @Param('id') id: string,
    @Body() dto: PayRequestDto,
  ) {
    return this.requests.pay(userId, id, dto.pin);
  }

  @Post(':id/decline')
  decline(@CurrentUser('userId') userId: string, @Param('id') id: string) {
    return this.requests.decline(userId, id);
  }

  @Post(':id/cancel')
  cancel(@CurrentUser('userId') userId: string, @Param('id') id: string) {
    return this.requests.cancel(userId, id);
  }
}
