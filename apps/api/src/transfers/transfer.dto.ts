import { IsEmail, IsInt, IsOptional, IsString } from 'class-validator';

export class TransferDto {
  /** Recipient user id (from contacts) — preferred. */
  @IsOptional()
  @IsString()
  toUserId?: string;

  /** OR recipient email — resolved server-side. */
  @IsOptional()
  @IsEmail()
  toEmail?: string;

  /** Amount in minor units (cents). */
  @IsInt()
  amount: number;

  @IsString()
  pin: string;
}
