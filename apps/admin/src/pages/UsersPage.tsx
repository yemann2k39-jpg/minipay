import { useCallback, useEffect, useState } from 'react';
import { api, ApiError } from '../api';
import { fmt, fmtDate } from '../format';
import type { AdminUser } from '../types';
import StatusBadge from '../components/StatusBadge';

type UserAction = 'freeze' | 'unfreeze';

export default function UsersPage() {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [confirmingId, setConfirmingId] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    setConfirmingId(null);
    try {
      setUsers(await api.getUsers());
    } catch (err) {
      // 401 is handled globally (token cleared, back to login).
      if (!(err instanceof ApiError && err.status === 401)) {
        setError(err instanceof Error ? err.message : 'Failed to load users.');
      }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function applyAction(user: AdminUser, action: UserAction) {
    setBusyId(user.id);
    setError(null);
    try {
      await api.setUserStatus(user.id, action);
      const nextStatus = action === 'freeze' ? 'FROZEN' : 'ACTIVE';
      setUsers((prev) =>
        prev.map((u) => (u.id === user.id ? { ...u, status: nextStatus } : u)),
      );
    } catch (err) {
      if (!(err instanceof ApiError && err.status === 401)) {
        setError(err instanceof Error ? err.message : 'Failed to update the user.');
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
          <h1>Users</h1>
          <p className="page-subtitle">
            {loading ? 'Loading…' : `${users.length} user${users.length === 1 ? '' : 's'}`}
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
              <th>Name</th>
              <th>Email</th>
              <th>Phone</th>
              <th>Role</th>
              <th>Status</th>
              <th className="num">Balance</th>
              <th>Created</th>
              <th className="actions-col">Actions</th>
            </tr>
          </thead>
          <tbody>
            {loading && users.length === 0 && (
              <tr>
                <td colSpan={8} className="empty">
                  Loading users…
                </td>
              </tr>
            )}
            {!loading && users.length === 0 && !error && (
              <tr>
                <td colSpan={8} className="empty">
                  No users found.
                </td>
              </tr>
            )}
            {users.map((user) => {
              const isFreeze = user.status === 'ACTIVE';
              const action: UserAction | null = isFreeze
                ? 'freeze'
                : user.status === 'FROZEN'
                  ? 'unfreeze'
                  : null;
              return (
                <tr key={user.id}>
                  <td className="strong">{user.displayName || '—'}</td>
                  <td>{user.email}</td>
                  <td>{user.phone || '—'}</td>
                  <td>{user.role}</td>
                  <td>
                    <StatusBadge status={user.status} />
                  </td>
                  <td className="num">{fmt(user.balanceMinor)}</td>
                  <td>{fmtDate(user.createdAt)}</td>
                  <td className="actions-col">
                    {action === null ? (
                      <span className="muted">—</span>
                    ) : confirmingId === user.id ? (
                      <span className="confirm-row">
                        <span className="confirm-text">
                          {isFreeze ? 'Freeze this user?' : 'Unfreeze this user?'}
                        </span>
                        <button
                          type="button"
                          className={`btn btn-sm ${isFreeze ? 'btn-danger' : 'btn-primary'}`}
                          disabled={busyId === user.id}
                          onClick={() => void applyAction(user, action)}
                        >
                          {busyId === user.id ? 'Working…' : 'Confirm'}
                        </button>
                        <button
                          type="button"
                          className="btn btn-sm btn-ghost"
                          disabled={busyId === user.id}
                          onClick={() => setConfirmingId(null)}
                        >
                          Cancel
                        </button>
                      </span>
                    ) : (
                      <button
                        type="button"
                        className={`btn btn-sm ${isFreeze ? 'btn-danger-outline' : 'btn-outline'}`}
                        disabled={busyId === user.id}
                        onClick={() => setConfirmingId(user.id)}
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
