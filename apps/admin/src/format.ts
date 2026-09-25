/** Format an amount in minor units (SGD cents) as a currency string. */
export const fmt = (minor: string | number): string =>
  (Number(minor) / 100).toLocaleString('en-SG', { style: 'currency', currency: 'SGD' });

const DATE_TIME_FORMAT = new Intl.DateTimeFormat('en-SG', {
  dateStyle: 'medium',
  timeStyle: 'short',
});

export function fmtDate(iso: string | null | undefined): string {
  if (!iso) return '—';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '—';
  return DATE_TIME_FORMAT.format(date);
}

/** Shorten an account id to its first 8 characters for table display. */
export function shortId(id: string | null | undefined): string {
  if (!id) return '—';
  return id.length <= 8 ? id : id.slice(0, 8);
}
