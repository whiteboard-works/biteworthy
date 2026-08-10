'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import {
  fetchModerationReviews,
  REVIEW_VISIBILITIES,
  type AdminReviewsResponse,
  type ReviewVisibility,
} from '../../../lib/admin/reviews';
import { friendlyAdminError } from '../../../lib/admin/shared';
import { Pagination } from '../_Pagination';
import { ReviewModRow } from './_ReviewModRow';

/**
 * /admin/reviews — review moderation. Defaults to the flagged queue
 * (reader-reported, not yet moderated); the hidden view exists to
 * audit + reverse past decisions. Rows mutate in place with the
 * server-returned payload so the visible state never guesses.
 */

const PAGE_SIZE = 25;

export default function AdminReviewsPage() {
  const [visibility, setVisibility] = useState<ReviewVisibility>('flagged');
  const [offset, setOffset] = useState(0);
  const [data, setData] = useState<AdminReviewsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setError(null);
    fetchModerationReviews({ visibility, limit: PAGE_SIZE, offset })
      .then((d) => {
        if (active) setData(d);
      })
      .catch((e: unknown) => {
        if (active) setError(friendlyAdminError(e));
      });
    return () => {
      active = false;
    };
  }, [visibility, offset]);

  const onModerated = (updated: AdminReviewsResponse['reviews'][number]) => {
    setData((prev) =>
      prev
        ? { ...prev, reviews: prev.reviews.map((r) => (r.id === updated.id ? updated : r)) }
        : prev,
    );
  };

  const onDeleted = (id: string) => {
    setData((prev) =>
      prev
        ? {
            ...prev,
            reviews: prev.reviews.filter((r) => r.id !== id),
            pagination: { ...prev.pagination, total: Math.max(0, prev.pagination.total - 1) },
          }
        : prev,
    );
  };

  return (
    <main data-testid="admin-reviews">
      <h1 className="text-bw-2xl font-bold text-zinc-900">Review moderation</h1>

      {/* Filter pills, not ARIA tabs — tab semantics promise keyboard
          behavior these don't have. */}
      <div className="mt-bw-4 flex flex-wrap items-center gap-bw-2 text-bw-sm">
        {REVIEW_VISIBILITIES.map((v) => (
          <button
            key={v}
            type="button"
            aria-pressed={visibility === v}
            onClick={() => {
              setVisibility(v);
              setOffset(0);
              // Clear the old tab's rows — stale rows under a new tab's
              // error banner misread as that tab's content.
              setData(null);
            }}
            data-testid={`reviews-visibility-${v}`}
            className={
              visibility === v
                ? 'rounded-bw-pill bg-bite px-bw-3 py-bw-1 font-semibold text-white'
                : 'rounded-bw-pill border border-zinc-300 px-bw-3 py-bw-1 font-semibold text-zinc-600 hover:border-bite hover:text-bite'
            }
          >
            {v}
          </button>
        ))}
      </div>

      {error && (
        <div
          role="alert"
          data-testid="reviews-error"
          className="mt-bw-4 rounded border border-red-300 bg-red-50 p-4 text-red-900"
        >
          {error}
        </div>
      )}

      {!data && !error && (
        <p role="status" className="mt-bw-4 text-bw-sm text-zinc-500">
          Loading reviews…
        </p>
      )}

      {data && data.reviews.length === 0 && (
        <p data-testid="reviews-empty" className="mt-bw-6 text-bw-sm text-zinc-500">
          {visibility === 'flagged' ? 'No flagged reviews. Inbox zero.' : 'Nothing here.'}
        </p>
      )}

      {data && data.reviews.length > 0 && (
        <div className="mt-bw-4 space-y-bw-4">
          <ul className="space-y-bw-3">
            {data.reviews.map((review) => (
              <ReviewModRow
                key={review.id}
                review={review}
                onModerated={onModerated}
                onDeleted={onDeleted}
              />
            ))}
          </ul>
          <Pagination
            total={data.pagination.total}
            limit={data.pagination.limit}
            offset={data.pagination.offset}
            onOffset={setOffset}
          />
        </div>
      )}

      <p className="mt-bw-6 text-bw-xs text-zinc-400">
        Hidden reviews stay visible to their author (with the reason) on{' '}
        <Link href="/profile/settings" className="underline">
          their account page
        </Link>
        .
      </p>
    </main>
  );
}
