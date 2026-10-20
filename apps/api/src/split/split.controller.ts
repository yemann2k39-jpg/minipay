import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  UseGuards,
} from '@nestjs/common';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { SplitService } from './split.service';

const IMAGE_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;

export class ScanReceiptDto {
  // ~5 MB binary -> ~6.8 MB base64 characters.
  @MaxLength(7_000_000)
  @IsString()
  imageBase64: string;

  @IsOptional()
  @IsIn(IMAGE_MIME_TYPES)
  mimeType?: string;
}

export class SplitItemDto {
  @IsString()
  @MaxLength(140)
  name: string;

  // SGD 0.01 – 5,000.00 in minor units (service re-checks).
  @IsInt()
  @Min(1)
  priceMinor: number;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(50)
  @IsUUID('4', { each: true })
  assignedUserIds?: string[]; // empty = split among all participants
}

export class CreateSplitDto {
  @IsString()
  @MaxLength(140)
  title: string;

  @IsArray()
  @ArrayMaxSize(50)
  @IsUUID('4', { each: true })
  participantUserIds: string[];

  @IsArray()
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => SplitItemDto)
  items: SplitItemDto[];

  // SGD 0.00 – 5,000.00 in minor units.
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(500000)
  extraMinor?: number;

  // SGD 0.00 – 5,000.00 in minor units. Discount subtracted from the total.
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(500000)
  discountMinor?: number;
}

export class SendSplitRequestsDto {
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(50)
  @IsUUID('4', { each: true })
  userIds?: string[]; // omit = all unsent participants
}

@Controller('split')
@UseGuards(JwtAuthGuard)
export class SplitController {
  constructor(private split: SplitService) {}

  @Post('scan')
  scan(@CurrentUser('userId') userId: string, @Body() dto: ScanReceiptDto) {
    const mime = dto.mimeType ?? 'image/jpeg';
    if (!(IMAGE_MIME_TYPES as readonly string[]).includes(mime)) {
      throw new BadRequestException('Unsupported image type');
    }
    return this.split.scan(userId, dto.imageBase64, mime);
  }

  @Post()
  create(@CurrentUser('userId') userId: string, @Body() dto: CreateSplitDto) {
    return this.split.create(userId, dto);
  }

  @Get()
  list(@CurrentUser('userId') userId: string) {
    return this.split.list(userId);
  }

  @Get(':id')
  detail(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.split.detail(userId, id);
  }

  /** Send money requests to participants (all unsent, or specific users). */
  @Post(':id/requests/send')
  sendRequests(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: SendSplitRequestsDto,
  ) {
    return this.split.sendRequests(userId, id, dto.userIds);
  }

  /** Delete a split — only while no requests have been sent. */
  @Delete(':id')
  delete(
    @CurrentUser('userId') userId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.split.delete(userId, id);
  }
}
