import { Type } from 'class-transformer';
import {
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export class CreateCheckoutDto {
  @IsString()
  @MaxLength(140)
  orderRef!: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(5_000_000)
  amountMinor!: number;

  @IsOptional()
  @IsString()
  @MaxLength(280)
  description?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  // Production callbacks must be HTTPS; localhost http is allowed for dev.
  @Matches(/^https:\/\/.+|^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?\/.*$/i, {
    message: 'callbackUrl must be an HTTPS URL (http allowed for localhost)',
  })
  callbackUrl?: string;
}
