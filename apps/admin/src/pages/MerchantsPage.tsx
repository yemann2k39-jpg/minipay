import { useCallback, useEffect, useState } from 'react';
import { api, ApiError } from '../api';
import { fmt, fmtDate } from '../format';
import type { AdminMerchant } from '../types';
import StatusBadge from '../components/StatusBadge';

type MerchantAction = 'freeze' | 'unfreeze';

export default function MerchantsPage() {
  const [merchants, setMerchants] = useState<AdminMerchant[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [confirmingId, setConfirmingId] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    setConfirmingId(null);
    try {
      setMerchants(await api.getMerchants());
    } catch (err) {
      // 401 is handled globally (token cleared, back to login).
      if (!(err instanceof ApiError && err.status === 401)) {
        setError(err instanceof Error ? err.message : 'Failed to load merchants.');
      }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function applyAction(merchant: AdminMerchant, action: MerchantAction) {
    setBusyId(merchant.id);
    setError(null);
    try {
      await api.setMerchantStatus(merchant.id, action);
      const nextStatus = action === 'freeze' ? 'FROZEN' : 'ACTIVE';
      setMerchants((prev) =>
        prev.map((m) => (m.id === merchant.id ? { ...m, status: nextStatus } : m)),
      );
    } catch (err) {
      if (!(err instanceof ApiError && err.status === 401)) {
        setError(err instanceof Error ? err.message : 'Failed to update the merchant.');
      }
    } finally {
      setBusyId(null);
      setConfirmingId(null);
    }
  }

  return (
    <section>
      <div className="page-header">
        <div>
          <h1>Merchants</h1>
          <p className="page-subtitle">
            {loading ? 'Loading…' : `${merchants.length} merchant${merchants.length === 1 ? '' : 's'}`}
          </p>
        </div>
        <button type="button" className="btn btn-outline" onClick={() => void load()} disabled={loading}>
          {loading ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>

      {error && <div className="alert alert-error">{error}</div>}

      <div className="card table-card">
        <table className="table">
          <thead>
            <tr>
              <th>Business</th>
              <th>Code</th>
              <th>Owner</th>
              <th>Status</th>
              <th className="num">Settlement balance</th>
              <th>Created</th>
              <th className="actions-col">Actions</th>
            </tr>
          </thead>
          <tbody>
            {loading && merchants.length === 0 && (
              <tr>
                <td colSpan={7} className="empty">
                  Loading merchants…
                </td>
              </tr>
            )}
            {!loading && merchants.length === 0 && !error && (
              <tr>
                <td colSpan={7} className="empty">
                  No merchants found.
                </td>
              </tr>
            )}
            {merchants.map((merchant) => {
              const isFreeze = merchant.status === 'ACTIVE';
              const action: MerchantAction | null = isFreeze
                ? 'freeze'
                : merchant.status === 'FROZEN'
                  ? 'unfreeze'
                  : null;
              return (
                <tr key={merchant.id}>
                  <td className="strong">{merchant.name}</td>
                  <td>{merchant.code}</td>
                  <td>
                    {merchant.owner ? (
                      <span>
                        {merchant.owner.displayName}{' '}
                        <span className="muted">({merchant.owner.email})</span>
                      </span>
                    ) : (
                      <span className="muted">—</span>
                    )}
                  </td>
                  <td>
                    <StatusBadge status={merchant.status} />
                  </td>
                  <td className="num">{fmt(merchant.balanceMinor)}</td>
                  <td>{fmtDate(merchant.createdAt)}</td>
                  <td className="actions-col">
                    {action === null ? (
                      <span className="muted">—</span>
                    ) : confirmingId === merchant.id ? (
                      <span className="confirm-row">
                        <span className="confirm-text">
                          {isFreeze
                            ? 'Freeze this merchant? New checkouts, payouts and refunds will be blocked.'
                            : 'Unfreeze this merchant?'}
                        </span>
                        <button
                          type="button"
                          className={`btn btn-sm ${isFreeze ? 'btn-danger' : 'btn-primary'}`}
                          disabled={busyId === merchant.id}
                          onClick={() => void applyAction(merchant, action)}
                        >
                          {busyId === merchant.id ? 'Working…' : 'Confirm'}
                        </button>
                        <button
                          type="button"
                          className="btn btn-sm btn-ghost"
                          disabled={busyId === merchant.id}
                          onClick={() => setConfirmingId(null)}
                        >
                          Cancel
                        </button>
                      </span>
                    ) : (
                      <button
                        type="button"
                        className={`btn btn-sm ${isFreeze ? 'btn-danger-outline' : 'btn-outline'}`}
                        disabled={busyId === merchant.id}
                        onClick={() => setConfirmingId(merchant.id)}
                      >
                        {isFreeze ? 'Freeze' : 'Unfreeze'}
                      </button>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </section>
  );
}
