'use client';

import { useState } from 'react';
import { updateAdminItem, type AdminItemRow } from '../../../../lib/admin/management';
import { friendlyAdminError } from '../../../../lib/admin/shared';
import { StatusBadge, type BadgeTone } from '../../_StatusBadge';

/**
 * One item in the restaurant workbench. The status select is the
 * admin unpublish lever ("removed" hides it from every public menu
 * read); confidence renders as a badge but is deliberately not
 * editable — that stays on the promote/confirm rails.
 */
const ITEM_STATUSES = ['draft', 'published', 'removed'] as const;

const STATUS_TONES: Record<string, BadgeTone> = {
  draft: 'muted',
  published: 'ok',
  removed: 'danger',
};

const CONFIDENCE_TONES: Record<string, BadgeTone> = {
  confirmed: 'ok',
  suggested: 'warn',
  inferred: 'muted',
};

export function AdminItemRowEditor({
  item,
  onUpdated,
}: {
  item: AdminItemRow;
  onUpdated: (updated: AdminItemRow) => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const setStatus = async (status: string) => {
    setBusy(true);
    setError(null);
    try {
      onUpdated(await updateAdminItem(item.id, { status }));
    } catch (e) {
      setError(friendlyAdminError(e));
    } finally {
      setBusy(false);
    }
  };

  const price = item.variants?.[0]?.price_cents;

  return (
    <li
      data-testid={`admin-item-${item.id}`}
      className="rounded-bw-lg border border-zinc-200 bg-white p-bw-3"
    >
      <div className="flex flex-wrap items-center justify-between gap-bw-2">
        <div className="min-w-0">
          <p className="font-semibold text-zinc-900">
            {item.name}
            {price != null && (
              <span className="ml-bw-2 font-normal text-zinc-500">
                ${(price / 100).toFixed(2)}
              </span>
            )}
          </p>
          <p className="mt-bw-1 text-bw-xs text-zinc-500">
            {item.ingredient_count ?? 0} ingredients · {item.tag_count ?? 0} tags
            {item.description && <> · {item.description}</>}
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-bw-2 text-bw-sm">
          <StatusBadge
            label={item.confidence}
            tone={CONFIDENCE_TONES[item.confidence] ?? 'muted'}
          />
          <StatusBadge label={item.status} tone={STATUS_TONES[item.status] ?? 'muted'} />
          <select
            value={item.status}
            onChange={(e) => void setStatus(e.target.value)}
            disabled={busy}
            data-testid={`admin-item-status-${item.id}`}
            className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 disabled:opacity-50"
          >
            {ITEM_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </div>
      </div>
      {error && (
        <p role="alert" className="mt-bw-2 text-bw-sm text-red-700">
          {error}
        </p>
      )}
    </li>
  );
}
