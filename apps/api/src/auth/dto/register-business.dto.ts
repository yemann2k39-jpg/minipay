import { IsEmail, IsNotEmpty, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class RegisterBusinessDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(8)
  password!: string;

  /** Owner's display name (the person, not the shop). */
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  displayName!: string;

  /** Business/trading name shown to customers and in the admin dashboard. */
  @IsString()
  @IsNotEmpty()
  @MaxLength(80)
  businessName!: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  phone?: string;
}
