import type { AdminStats, AdminUser, LoginResponse, Transaction } from './types';

const TOKEN_KEY = 'wallet_admin_access_token';

// Token is kept in memory and mirrored to localStorage for convenience
// (survives a page refresh; cleared on logout and on 401).
let accessToken: string | null = window.localStorage.getItem(TOKEN_KEY);

export function getToken(): string | null {
  return accessToken;
}

export function setToken(token: string | null): void {
  accessToken = token;
  if (token) {
    window.localStorage.setItem(TOKEN_KEY, token);
  } else {
    window.localStorage.removeItem(TOKEN_KEY);
  }
}

/** Fired (on window) whenever an authenticated API call gets a 401. */
export const UNAUTHORIZED_EVENT = 'admin:unauthorized';

export class ApiError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
  }
}

interface RequestOptions {
  method?: 'GET' | 'POST';
  body?: unknown;
  /**
   * When true (default), a 401 response clears the token and notifies the app
   * so it can return to the login page. The login endpoint itself opts out.
   */
  handle401?: boolean;
}

async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = {};
  if (options.body !== undefined) {
    headers['Content-Type'] = 'application/json';
  }
  if (accessToken) {
    headers['Authorization'] = `Bearer ${accessToken}`;
  }

  let res: Response;
  try {
    res = await fetch(`/api${path}`, {
      method: options.method ?? 'GET',
      headers,
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
    });
  } catch {
    throw new ApiError(0, 'Cannot reach the API. Please check that the backend is running.');
  }

  if (res.status === 401 && options.handle401 !== false) {
    setToken(null);
    window.dispatchEvent(new CustomEvent(UNAUTHORIZED_EVENT));
    throw new ApiError(401, 'Your session has expired. Please sign in again.');
  }

  if (!res.ok) {
    throw new ApiError(res.status, await extractErrorMessage(res));
  }

  return (await res.json()) as T;
}

async function extractErrorMessage(res: Response): Promise<string> {
  try {
    const data: unknown = await res.json();
    if (data && typeof data === 'object') {
      const message = (data as { message?: unknown }).message;
      if (typeof message === 'string' && message.trim() !== '') {
        return message;
      }
      if (Array.isArray(message) && message.length > 0) {
        return message.join(', ');
      }
    }
  } catch {
    // Response had no JSON body; fall through to the generic message.
  }
  return `Request failed with status ${res.status}.`;
}

export const api = {
  login(email: string, password: string): Promise<LoginResponse> {
    return request<LoginResponse>('/auth/login', {
      method: 'POST',
      body: { email, password },
      handle401: false,
    });
  },
  getStats(): Promise<AdminStats> {
    return request<AdminStats>('/admin/stats');
  },
  getUsers(): Promise<AdminUser[]> {
    return request<AdminUser[]>('/admin/users');
  },
  setUserStatus(id: string, action: 'freeze' | 'unfreeze'): Promise<{ success: boolean }> {
    return request<{ success: boolean }>(
      `/admin/users/${encodeURIComponent(id)}/${action}`,
      { method: 'POST' },
    );
  },
  getTransactions(take = 50): Promise<Transaction[]> {
    return request<Transaction[]>(`/admin/transactions?take=${take}`);
  },
};
