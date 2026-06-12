'use client';

import { useState } from 'react';
import {
  decideRunItem,
  friendlyIngestionError,
  type IngestionItemPayload,
} from '../../../../lib/ingestion';

/**
 * Phase 6.5 — one staged item in the web verify list. The web twin
 * of mobile's swipe-verify card (Phase 2.7): accept promotes (with
 * the Phase 6.3 trust level of whoever is signed in), reject buries.
 */
export function VerifyItemRow({
  runId,
  item,
  onDecided,
}: {
  runId: string;
  item: IngestionItemPayload;
  onDecided: (updated: IngestionItemPayload) => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const decide = async (decision: 'accepted' | 'rejected') => {
    setError(null);
    try {
      setBusy(true);
      const updated = await decideRunItem({ runId, itemId: item.id, decision });
      onDecided(updated);
    } catch (e) {
      setError(friendlyIngestionError(e));
    } finally {
      setBusy(false);
    }
  };

  const decided = item.decision === 'accepted' || item.decision === 'rejected';
  const price = item.prices_payload[0]?.price_cents;

  return (
    <li className="rounded-xl border border-zinc-200 p-4" data-testid={`verify-item-${item.id}`}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="font-semibold">
            {item.name}
            {price != null && (
              <span className="ml-2 font-normal text-zinc-500">
                ${(price / 100).toFixed(2)}
              </span>
            )}
          </p>
          {item.section_name && (
            <p className="text-xs uppercase tracking-wide text-zinc-400">{item.section_name}</p>
          )}
          {item.description && <p className="mt-1 text-sm text-zinc-600">{item.description}</p>}
          <p className="mt-2 flex flex-wrap gap-1">
            {item.ingredients_payload.map((row) => (
              <span
                key={row.slug}
                className="rounded-full bg-zinc-100 px-2 py-0.5 text-xs text-zinc-700"
              >
                {row.slug}
              </span>
            ))}
            {item.tags_payload.map((row) => (
              <span
                key={row.slug}
                className="rounded-full bg-orange-50 px-2 py-0.5 text-xs text-orange-700"
              >
                {row.slug}
              </span>
            ))}
          </p>
        </div>

        <div className="flex shrink-0 flex-col items-end gap-2">
          {decided ? (
            <span
              className={
                item.decision === 'accepted'
                  ? 'rounded bg-green-100 px-2 py-1 text-sm font-semibold text-green-800'
                  : 'rounded bg-zinc-100 px-2 py-1 text-sm font-semibold text-zinc-600'
              }
            >
              {item.decision}
            </span>
          ) : (
            <>
              <button
                type="button"
                disabled={busy}
                onClick={() => void decide('accepted')}
                className="rounded bg-green-600 px-3 py-1 text-sm font-semibold text-white disabled:opacity-50"
              >
                Accept
              </button>
              <button
                type="button"
                disabled={busy}
                onClick={() => void decide('rejected')}
                className="rounded border border-zinc-300 px-3 py-1 text-sm font-semibold text-zinc-600 disabled:opacity-50"
              >
                Reject
              </button>
            </>
          )}
        </div>
      </div>
      {error && (
        <p className="mt-2 text-sm text-red-700" role="alert">
          {error}
        </p>
      )}
    </li>
  );
}
