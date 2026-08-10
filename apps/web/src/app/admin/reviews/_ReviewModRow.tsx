'use client';

import { useState } from 'react';
import {
  HIDE_REASONS,
  hideReview,
  unhideReview,
  type AdminReviewRow,
  type HideReason,
} from '../../../lib/admin/reviews';
import { destroyAdminReview } from '../../../lib/admin/deletes';
import { friendlyAdminError } from '../../../lib/admin/shared';
import { HardDeleteButton } from '../_HardDeleteButton';
import { StatusBadge } from '../_StatusBadge';

/**
 * One review in the moderation queue. Hide requires picking a reason
 * first (it becomes the author-facing "why was this hidden" copy);
 * unhide fully restores. The row swaps to the server-returned payload
 * on success — never an optimistic guess.
 */
export function ReviewModRow({
  review,
  onModerated,
  onDeleted,
}: {
  review: AdminReviewRow;
  onModerated: (updated: AdminReviewRow) => void;
  onDeleted: (id: string) => void;
}) {
  const [reason, setReason] = useState<HideReason>('spam');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const act = async (fn: () => Promise<AdminReviewRow>) => {
    setBusy(true);
    setError(null);
    try {
      onModerated(await fn());
    } catch (e) {
      setError(friendlyAdminError(e));
    } finally {
      setBusy(false);
    }
  };

  const hidden = Boolean(review.hidden_at);

  return (
    <li
      data-testid={`review-mod-${review.id}`}
      className="rounded-bw-lg border border-zinc-200 bg-white p-bw-4"
    >
      <div className="flex flex-wrap items-start justify-between gap-bw-3">
        <div className="min-w-0">
          <p className="text-bw-sm text-zinc-500">
            <span className="font-semibold text-zinc-900">{review.user?.handle ?? 'unknown'}</span>{' '}
            on <span className="font-semibold text-zinc-900">{review.item?.name ?? '—'}</span>
            {review.item?.restaurant?.name && <> at {review.item.restaurant.name}</>}
            {review.rating != null && <> · {review.rating}★</>}
          </p>
          {review.body && <p className="mt-bw-1 text-bw-sm text-zinc-800">{review.body}</p>}
          {review.photo_url && (
            <p className="mt-bw-1 text-bw-xs text-zinc-500">
              <a href={review.photo_url} target="_blank" rel="noreferrer" className="underline">
                Attached photo
              </a>
            </p>
          )}
        </div>
        <div className="shrink-0">
          {hidden ? (
            <StatusBadge tone="danger" label={`hidden: ${review.hidden_reason ?? '?'}`} />
          ) : review.flagged_at ? (
            <StatusBadge tone="warn" label="flagged" />
          ) : (
            <StatusBadge tone="ok" label="visible" />
          )}
        </div>
      </div>

      <div className="mt-bw-3 flex flex-wrap items-center gap-bw-2 text-bw-sm">
        {hidden ? (
          <button
            type="button"
            onClick={() => void act(() => unhideReview(review.id))}
            disabled={busy}
            data-testid={`review-unhide-${review.id}`}
            className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1 font-semibold text-zinc-700 hover:border-ok hover:text-ok disabled:opacity-50"
          >
            {busy ? 'Restoring…' : 'Unhide'}
          </button>
        ) : (
          <>
            <label className="flex items-center gap-bw-2 text-zinc-600">
              Reason
              <select
                value={reason}
                onChange={(e) => setReason(e.target.value as HideReason)}
                data-testid={`review-reason-${review.id}`}
                className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
              >
                {HIDE_REASONS.map((r) => (
                  <option key={r} value={r}>
                    {r}
                  </option>
                ))}
              </select>
            </label>
            <button
              type="button"
              onClick={() => void act(() => hideReview(review.id, reason))}
              disabled={busy}
              data-testid={`review-hide-${review.id}`}
              className="rounded-bw-md bg-danger px-bw-3 py-bw-1 font-semibold text-white disabled:opacity-50"
            >
              {busy ? 'Hiding…' : 'Hide'}
            </button>
          </>
        )}
        {/* Hiding records WHY, from a closed list of editorial reasons,
            and is what moderation normally wants. Delete is for the row
            that should never have existed — it leaves no reason behind
            because there is no row left to explain. */}
        <HardDeleteButton
          onDelete={() => destroyAdminReview(review.id)}
          onDeleted={() => onDeleted(review.id)}
          disabled={busy}
          testId={`review-delete-${review.id}`}
        />
      </div>

      {error && (
        <p role="alert" className="mt-bw-2 text-bw-sm text-red-700">
          {error}
        </p>
      )}
    </li>
  );
}
