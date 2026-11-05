export type UserStatus = 'ACTIVE' | 'FROZEN' | 'CLOSED';

export type TransactionType =
  | 'DEPOSIT'
  | 'TRANSFER'
  | 'MERCHANT_PAYMENT'
  | 'REQUEST_PAYMENT'
  | 'REFUND';

export type TransactionStatus = 'PENDING' | 'COMPLETED' | 'FAILED';

export interface AuthUser {
  id: string;
  email: string;
  role: string;
  displayName?: string | null;
}

export interface LoginResponse {
  accessToken: string;
  refreshToken: string;
  user: AuthUser;
}

export interface AdminUser {
  id: string;
  email: string;
  displayName?: string | null;
  phone?: string | null;
  role: string;
  status: UserStatus;
  balanceMinor: string;
  createdAt: string;
}

export interface Transaction {
  id: string;
  type: TransactionType;
  status: TransactionStatus;
  amount: string;
  currency: string;
  fromAccountId?: string | null;
  toAccountId?: string | null;
  createdAt: string;
  completedAt?: string | null;
}

export interface AdminStats {
  users: number;
  activeUsers: number;
  transactions: number;
  volumeMinor: string;
}

export interface MerchantOwner {
  email: string;
  displayName: string;
  status: UserStatus;
}

export interface AdminMerchant {
  id: string;
  code: string;
  name: string;
  status: UserStatus;
  callbackUrl?: string | null;
  ledgerAccountId: string;
  balanceMinor: string;
  owner: MerchantOwner | null;
  createdAt: string;
}
