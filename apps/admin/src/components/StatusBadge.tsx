const BADGE_CLASS: Record<string, string> = {
  ACTIVE: 'badge badge-green',
  COMPLETED: 'badge badge-green',
  FROZEN: 'badge badge-orange',
  PENDING: 'badge badge-gray',
  CLOSED: 'badge badge-gray',
  FAILED: 'badge badge-red',
};

interface StatusBadgeProps {
  status: string;
}

export default function StatusBadge({ status }: StatusBadgeProps) {
  return <span className={BADGE_CLASS[status] ?? 'badge badge-gray'}>{status}</span>;
}
