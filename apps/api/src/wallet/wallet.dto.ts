import { IsIn, IsInt } from 'class-validator';

export class CreateDepositDto {
  /** Amount in minor units (cents). SGD 10.00 => 1000 */
  @IsInt()
  amount: number;
}

export class ConfirmTestDepositDto {
  @IsIn(['visa', 'visa_debit', 'mastercard'])
  card: string;
}
