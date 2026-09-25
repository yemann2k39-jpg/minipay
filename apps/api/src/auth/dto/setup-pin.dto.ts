import { IsString, Matches } from 'class-validator';

export class SetupPinDto {
  @IsString()
  @Matches(/^\d{6}$/, { message: 'PIN must be exactly 6 digits' })
  pin: string;
}
