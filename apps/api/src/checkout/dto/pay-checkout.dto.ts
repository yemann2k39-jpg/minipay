import { Type } from 'class-transformer';
import { IsEmail, IsOptional, IsString, Length, Matches } from 'class-validator';

export class PayCheckoutDto {
  @IsString()
  @Length(6, 6)
  @Matches(/^\d{6}$/, { message: 'PIN must be exactly 6 digits' })
  pin!: string;
}

export class PayCheckoutWebDto {
  @IsString()
  @Length(3, 254)
  email!: string;

  @IsString()
  @Length(6, 6)
  @Matches(/^\d{6}$/, { message: 'PIN must be exactly 6 digits' })
  pin!: string;
}
