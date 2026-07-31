/**
 * Small labeled pill for state (spend headroom, run status, review
 * visibility). Tones map to the ui-tokens status colors; the label is
 * always text — state is never conveyed by color alone.
 */
const TONES = {
  ok: 'border-ok/40 bg-ok/10 text-ok',
  warn: 'border-warn/40 bg-warn/10 text-warn',
  danger: 'border-danger/40 bg-danger/10 text-danger',
  muted: 'border-zinc-200 bg-zinc-100 text-zinc-600',
  // Brand accent for role markers (the "admin" pill) — not a status.
  bite: 'border-bite/40 bg-bite/10 text-bite',
} as const;

export type BadgeTone = keyof typeof TONES;

export function StatusBadge({ label, tone }: { label: string; tone: BadgeTone }) {
  return (
    <span
      data-testid="status-badge"
      data-tone={tone}
      className={`inline-flex items-center whitespace-nowrap rounded-bw-pill border px-bw-2 py-bw-1 text-bw-xs font-semibold ${TONES[tone]}`}
    >
      {label}
    </span>
  );
}
