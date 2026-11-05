/** Pure formatting/escaping helpers for the hosted checkout page. */
export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function formatSgd(amountMinor: bigint): string {
  return `S$${(Number(amountMinor) / 100).toFixed(2)}`;
}
