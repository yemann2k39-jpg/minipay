import { useCallback, useEffect, useState } from 'react';
import { api, ApiError } from '../api';
import { fmt, fmtDate, shortId } from '../format';
import type { Transaction, TransactionType } from '../types';
import StatusBadge from '../components/StatusBadge';

const TYPE_LABELS: Record<TransactionType, string> = {
  DEPOSIT: 'Deposit',
  TRANSFER: 'Transfer',
  MERCHANT_PAYMENT: 'Merchant payment',
  REQUEST_PAYMENT: 'Request payment',
};

function typeLabel(type: string): string {
  return TYPE_LABELS[type as TransactionType] ?? type;
}

export default function TransactionsPage() {
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setTransactions(await api.getTransactions());
    } catch (err) {
      // 401 is handled globally (token cleared, back to login).
      if (!(err instanceof ApiError && err.status === 401)) {
        setError(err instanceof Error ? err.message : 'Failed to load transactions.');
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
          <h1>Transactions</h1>
          <p className="page-subtitle">
            {loading ? 'Loading…' : `${transactions.length} most recent transactions`}
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
              <th>Type</th>
              <th>Status</th>
              <th className="num">Amount (SGD)</th>
              <th>From account</th>
              <th>To account</th>
              <th>Created</th>
            </tr>
          </thead>
          <tbody>
            {loading && transactions.length === 0 && (
              <tr>
                <td colSpan={6} className="empty">
                  Loading transactions…
                </td>
              </tr>
            )}
            {!loading && transactions.length === 0 && !error && (
              <tr>
                <td colSpan={6} className="empty">
                  No transactions found.
                </td>
              </tr>
            )}
            {transactions.map((tx) => (
              <tr key={tx.id}>
                <td className="strong">{typeLabel(tx.type)}</td>
                <td>
                  <StatusBadge status={tx.status} />
                </td>
                <td className="num">{fmt(tx.amount)}</td>
                <td>
                  <span className="mono" title={tx.fromAccountId ?? undefined}>
                    {shortId(tx.fromAccountId)}
                  </span>
                </td>
                <td>
                  <span className="mono" title={tx.toAccountId ?? undefined}>
                    {shortId(tx.toAccountId)}
                  </span>
                </td>
                <td>{fmtDate(tx.createdAt)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
