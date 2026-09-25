import { useState } from 'react';
import type { FormEvent } from 'react';
import { api, ApiError, setToken } from '../api';

interface LoginPageProps {
  onLogin: (accessToken: string) => void;
}

export default function LoginPage({ onLogin }: LoginPageProps) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const result = await api.login(email.trim(), password);
      if (result.user?.role !== 'ADMIN') {
        // Not an admin: make sure no token lingers, stay on the login page.
        setToken(null);
        setError('Admin access only');
        return;
      }
      onLogin(result.accessToken);
    } catch (err) {
      setError(
        err instanceof ApiError
          ? err.status === 401
            ? 'Invalid email or password.'
            : err.message
          : 'Login failed. Please check your connection and try again.',
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login-wrap">
      <form className="login-card" onSubmit={handleSubmit}>
        <div className="login-brand">
          <span className="brand-mark">W</span>
          <h1>Wallet Admin</h1>
          <p className="page-subtitle">Sign in to the payment wallet admin console.</p>
        </div>

        {error && (
          <div className="alert alert-error" role="alert">
            {error}
          </div>
        )}

        <label className="field">
          <span>Email</span>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="username"
            placeholder="admin@example.com"
            required
          />
        </label>

        <label className="field">
          <span>Password</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
            placeholder="••••••••"
            required
          />
        </label>

        <button type="submit" className="btn btn-primary btn-block" disabled={busy}>
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </div>
  );
}
