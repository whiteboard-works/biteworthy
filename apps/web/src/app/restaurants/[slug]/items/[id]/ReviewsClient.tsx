'use client';

import { useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import {
  createReview,
  fetchReviews,
  ReviewError,
  type ReviewPayload,
  type ReviewsResponse,
} from '../../../../../lib/reviews';
import { useTracker } from '../../../../_PostHogProvider';

/**
 * Phase 4.5 — client island for the SSR item detail page.
 *
 * Renders the reviews list (seeded from SSR), the inline compose
 * form, and a "Load more" button when there are more than 20
 * reviews. Anonymous compose attempts bounce to /login; the rest
 * of the page (item header, breadcrumb, initial reviews) is always
 * server-rendered for SEO.
 */
const PAGE_SIZE = 20;

export function ReviewsClient({
  itemId,
  restaurantSlug,
  initial,
}: {
  itemId: string;
  restaurantSlug: string;
  initial: ReviewsResponse;
}) {
  const router = useRouter();

  const [reviews, setReviews] = useState<ReviewPayload[]>(initial.reviews);
  const [total, setTotal] = useState(initial.total);
  const [loadingMore, setLoadingMore] = useState(false);
  const [composerOpen, setComposerOpen] = useState(false);

  const loadMore = async () => {
    try {
      setLoadingMore(true);
      const next = await fetchReviews(itemId, { offset: reviews.length, limit: PAGE_SIZE });
      setReviews((prev) => [...prev, ...next.reviews]);
      setTotal(next.total);
    } catch {
      // Best-effort — surface as a quiet console warning, no toast.
    } finally {
      setLoadingMore(false);
    }
  };

  const onPosted = (saved: ReviewPayload) => {
    setReviews((prev) => [saved, ...prev]);
    setTotal((n) => n + 1);
    setComposerOpen(false);
  };

  return (
    <section className="mt-bw-6">
      <div className="flex items-center justify-between">
        <h2 className="text-bw-lg font-bold">
          {total} review{total === 1 ? '' : 's'}
        </h2>
        {!composerOpen && (
          <button
            type="button"
            onClick={() => setComposerOpen(true)}
            data-testid="open-composer"
            className="rounded-bw-md bg-bite px-bw-3 py-bw-2 text-bw-sm font-bold text-white hover:bg-bite-dark"
          >
            Write a review
          </button>
        )}
      </div>

      {composerOpen && (
        <Composer
          itemId={itemId}
          restaurantSlug={restaurantSlug}
          onCancel={() => setComposerOpen(false)}
          onPosted={onPosted}
          onUnauthenticated={() => {
            router.replace(
              `/login?next=${encodeURIComponent(`/restaurants/_/items/${itemId}`)}`,
            );
          }}
        />
      )}

      <ul className="mt-bw-4 divide-y divide-zinc-100">
        {reviews.map((r) => (
          <ReviewCard key={r.id} review={r} />
        ))}
        {reviews.length === 0 && (
          <li className="py-bw-6 text-center text-bw-sm text-zinc-500">
            No reviews yet — be the first.
          </li>
        )}
      </ul>

      {reviews.length < total && (
        <button
          type="button"
          onClick={loadMore}
          disabled={loadingMore}
          data-testid="load-more"
          className="mt-bw-4 w-full rounded-bw-md border border-zinc-200 bg-white px-bw-3 py-bw-2 text-bw-sm font-semibold text-zinc-700 hover:border-zinc-300"
        >
          {loadingMore ? 'Loading…' : `Load more (${total - reviews.length} remaining)`}
        </button>
      )}
    </section>
  );
}

function ReviewCard({ review }: { review: ReviewPayload }) {
  return (
    <li className="py-bw-3" data-testid={`review-${review.id}`}>
      <p className="text-bw-sm font-semibold text-zinc-900">
        {review.user.display_name ?? review.user.handle ?? 'Diner'}{' '}
        <span className="text-bite">
          {'★'.repeat(review.rating)}
          <span className="text-zinc-300">{'☆'.repeat(5 - review.rating)}</span>
        </span>
      </p>
      {review.body && (
        <p className="mt-1 text-bw-base text-zinc-700">{review.body}</p>
      )}
      {review.photo_url && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={review.photo_url}
          alt="Reviewer's photo"
          className="mt-bw-2 max-h-80 w-full rounded-bw-md object-cover"
        />
      )}
    </li>
  );
}

function Composer({
  itemId,
  restaurantSlug,
  onCancel,
  onPosted,
  onUnauthenticated,
}: {
  itemId: string;
  restaurantSlug: string;
  onCancel: () => void;
  onPosted: (saved: ReviewPayload) => void;
  onUnauthenticated: () => void;
}) {
  const tracker = useTracker();
  const [rating, setRating] = useState(0);
  const [body, setBody] = useState('');
  const [photo, setPhoto] = useState<File | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (rating < 1 || rating > 5) {
      setError('Pick a rating first.');
      return;
    }
    try {
      setSubmitting(true);
      const saved = await createReview(itemId, {
        rating,
        body: body.trim() || undefined,
        photo,
      });
      tracker.track('review_posted', {
        item_slug: itemId,
        restaurant_slug: restaurantSlug,
        rating,
        has_photo: photo !== null,
      });
      onPosted(saved);
    } catch (e) {
      if (e instanceof ReviewError && e.status === 401) {
        onUnauthenticated();
        return;
      }
      setError((e as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <form onSubmit={onSubmit} className="mt-bw-4 rounded-bw-md border border-zinc-200 p-bw-4" data-testid="review-composer">
      <p className="text-bw-sm font-semibold text-zinc-700">How was it?</p>
      <div className="mt-bw-2 flex items-center gap-1">
        {[1, 2, 3, 4, 5].map((n) => (
          <button
            type="button"
            key={n}
            onClick={() => setRating(n)}
            data-testid={`star-${n}`}
            aria-pressed={rating >= n}
            className={['text-3xl', rating >= n ? 'text-bite' : 'text-zinc-300'].join(' ')}
          >
            ★
          </button>
        ))}
      </div>

      <textarea
        value={body}
        onChange={(e) => setBody(e.target.value)}
        placeholder="Optional notes — what was good, what wasn't"
        aria-label="review-body"
        className="mt-bw-3 w-full rounded-bw-md border border-zinc-300 p-bw-2 text-bw-base"
        rows={3}
      />

      <label className="mt-bw-2 block text-bw-sm font-semibold text-zinc-700">
        Photo (optional)
        <input
          type="file"
          accept="image/jpeg,image/png,image/heic,image/heif,image/webp"
          onChange={(e) => setPhoto(e.target.files?.[0] ?? null)}
          aria-label="photo"
          className="mt-1 block w-full text-bw-sm"
        />
      </label>

      {error && (
        <p className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          {error}
        </p>
      )}

      <div className="mt-bw-3 flex items-center gap-bw-2 justify-end">
        <button
          type="button"
          onClick={onCancel}
          className="rounded-bw-md border border-zinc-200 bg-white px-bw-3 py-bw-2 text-bw-sm font-semibold text-zinc-700 hover:border-zinc-300"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={submitting}
          data-testid="submit-review"
          className={[
            'rounded-bw-md bg-bite px-bw-4 py-bw-2 text-bw-sm font-bold text-white',
            submitting ? 'opacity-60' : 'hover:bg-bite-dark',
          ].join(' ')}
        >
          {submitting ? 'Posting…' : 'Post review'}
        </button>
      </div>
    </form>
  );
}
