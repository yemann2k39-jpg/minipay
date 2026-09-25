import { useCallback, useEffect, useState } from 'react';
import { api, ApiError } from '../api';
import { fmt } from '../format';
import type { AdminStats } from '../types';

export default function DashboardPage() {
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setStats(await api.getStats());
    } catch (err) {
      // 401 is handled globally (token cleared, back to login).
      if (!(err instanceof ApiError && err.status === 401)) {
        setError(err instanceof Error ? err.message : 'Failed to load dashboard stats.');
      }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <section>
      <div className="page-header">
        <div>
          <h1>Dashboard</h1>
          <p className="page-subtitle">Overview of the payment wallet.</p>
        </div>
        <button type="button" className="btn btn-outline" onClick={() => void load()} disabled={loading}>
          {loading ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>

      {error && <div className="alert alert-error">{error}</div>}

      <div className="stat-grid">
        <StatCard label="Total users" value={stats ? String(stats.users) : '—'} loading={loading} />
        <StatCard label="Active users" value={stats ? String(stats.activeUsers) : '—'} loading={loading} />
        <StatCard label="Transactions" value={stats ? String(stats.transactions) : '—'} loading={loading} />
        <StatCard label="Total volume (SGD)" value={stats ? fmt(stats.volumeMinor) : '—'} loading={loading} />
      </div>
    </section>
  );
}

function StatCard({ label, value, loading }: { label: string; value: string; loading: boolean }) {
  return (
    <div className="stat-card">
      <div className="stat-label">{label}</div>
      <div className={`stat-value${loading ? ' loading' : ''}`}>{value}</div>
    </div>
  );
}
