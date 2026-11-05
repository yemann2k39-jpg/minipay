import { useCallback, useEffect, useState } from 'react';
import { getToken, setToken, UNAUTHORIZED_EVENT } from './api';
import LoginPage from './pages/LoginPage';
import DashboardPage from './pages/DashboardPage';
import UsersPage from './pages/UsersPage';
import TransactionsPage from './pages/TransactionsPage';
import MerchantsPage from './pages/MerchantsPage';

type View = 'dashboard' | 'users' | 'merchants' | 'transactions';

const NAV_ITEMS: ReadonlyArray<{ key: View; label: string }> = [
  { key: 'dashboard', label: 'Dashboard' },
  { key: 'users', label: 'Users' },
  { key: 'merchants', label: 'Merchants' },
  { key: 'transactions', label: 'Transactions' },
];

export default function App() {
  const [token, setTokenState] = useState<string | null>(() => getToken());
  const [view, setView] = useState<View>('dashboard');

  // Any API call that receives a 401 clears the stored token and fires this
  // event, which drops us back to the login page.
  useEffect(() => {
    const handleUnauthorized = () => setTokenState(null);
    window.addEventListener(UNAUTHORIZED_EVENT, handleUnauthorized);
    return () => window.removeEventListener(UNAUTHORIZED_EVENT, handleUnauthorized);
  }, []);

  const handleLogin = useCallback((accessToken: string) => {
    setToken(accessToken);
    setTokenState(accessToken);
    setView('dashboard');
  }, []);

  const handleLogout = useCallback(() => {
    setToken(null);
    setTokenState(null);
  }, []);

  if (!token) {
    return <LoginPage onLogin={handleLogin} />;
  }

  return (
    <div className="app">
      <header className="topnav">
        <div className="topnav-inner">
          <div className="brand">
            <span className="brand-mark">W</span>
            <span>Wallet Admin</span>
          </div>
          <nav className="nav-links" aria-label="Main navigation">
            {NAV_ITEMS.map((item) => (
              <button
                key={item.key}
                type="button"
                className={`nav-link${view === item.key ? ' active' : ''}`}
                onClick={() => setView(item.key)}
              >
                {item.label}
              </button>
            ))}
          </nav>
          <button type="button" className="btn btn-ghost" onClick={handleLogout}>
            Log out
          </button>
        </div>
      </header>

      <main className="page">
        {view === 'dashboard' && <DashboardPage />}
        {view === 'users' && <UsersPage />}
        {view === 'merchants' && <MerchantsPage />}
        {view === 'transactions' && <TransactionsPage />}
      </main>
    </div>
  );
}
