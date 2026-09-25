import { IsInt, IsString, Matches } from 'class-validator';

export class MerchantPayDto {
  @IsString()
  @Matches(/^MP-[A-Z0-9]{3,10}$/, { message: 'Invalid merchant code' })
  merchantCode: string;

  /** Amount in minor units (cents). */
  @IsInt()
  amount: number;

  @IsString()
  pin: string;
}
