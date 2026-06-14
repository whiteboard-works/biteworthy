'use client';

import { useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import {
  createReview,
  deleteReview,
  fetchReviews,
  reportReview,
  updateReview,
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
  currentUserId = null,
}: {
  itemId: string;
  restaurantSlug: string;
  initial: ReviewsResponse;
  /** Legal remediation E11 — drives the owner-only edit/delete controls. */
  currentUserId?: string | null;
}) {
  const router = useRouter();

  const [reviews, setReviews] = useState<ReviewPayload[]>(initial.reviews);
  const [total, setTotal] = useState(initial.total);
  const [loadingMore, setLoadingMore] = useState(false);
  const [composerOpen, setComposerOpen] = useState(false);

  // E11 — keep the local list in sync after an in-place edit / delete.
  const onUpdated = (saved: ReviewPayload) =>
    setReviews((prev) => prev.map((r) => (r.id === saved.id ? saved : r)));
  const onDeleted = (id: string) => {
    setReviews((prev) => prev.filter((r) => r.id !== id));
    setTotal((n) => Math.max(0, n - 1));
  };

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
          <ReviewCard
            key={r.id}
            review={r}
            isOwner={currentUserId != null && r.user.id === currentUserId}
            onUpdated={onUpdated}
            onDeleted={onDeleted}
          />
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

function ReviewCard({
  review,
  isOwner,
  onUpdated,
  onDeleted,
}: {
  review: ReviewPayload;
  isOwner: boolean;
  onUpdated: (saved: ReviewPayload) => void;
  onDeleted: (id: string) => void;
}) {
  // E11 — the author can edit their own review inline or delete it.
  const [editing, setEditing] = useState(false);

  if (editing) {
    return (
      <li className="py-bw-3" data-testid={`review-${review.id}`}>
        <EditReviewForm
          review={review}
          onCancel={() => setEditing(false)}
          onSaved={(saved) => {
            onUpdated(saved);
            setEditing(false);
          }}
        />
      </li>
    );
  }

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
      {isOwner ? (
        <OwnerControls
          reviewId={review.id}
          onEdit={() => setEditing(true)}
          onDeleted={() => onDeleted(review.id)}
        />
      ) : (
        <ReportControl reviewId={review.id} />
      )}
    </li>
  );
}

/**
 * Legal remediation E11 — owner-only edit/delete. The author can
 * correct or remove their own review (the Privacy Policy "correct your
 * data" right, in-app rather than by email). The API still gates by
 * ownership; these controls only render for the author.
 */
function OwnerControls({
  reviewId,
  onEdit,
  onDeleted,
}: {
  reviewId: string;
  onEdit: () => void;
  onDeleted: () => void;
}) {
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const remove = async () => {
    setBusy(true);
    setError(null);
    try {
      await deleteReview(reviewId);
      onDeleted();
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  };

  return (
    <div className="mt-1 flex items-center gap-bw-3">
      <button
        type="button"
        onClick={onEdit}
        data-testid={`edit-${reviewId}`}
        className="text-bw-xs font-semibold text-bite hover:text-bite-dark"
      >
        Edit
      </button>
      {confirming ? (
        <>
          <span className="text-bw-xs text-zinc-500">Delete this review?</span>
          <button
            type="button"
            onClick={remove}
            disabled={busy}
            data-testid={`confirm-delete-${reviewId}`}
            className="text-bw-xs font-semibold text-bite-dark hover:underline"
          >
            {busy ? 'Deleting…' : 'Yes, delete'}
          </button>
          <button
            type="button"
            onClick={() => setConfirming(false)}
            className="text-bw-xs font-semibold text-zinc-400 hover:text-zinc-600"
          >
            Cancel
          </button>
        </>
      ) : (
        <button
          type="button"
          onClick={() => setConfirming(true)}
          data-testid={`delete-${reviewId}`}
          className="text-bw-xs font-semibold text-zinc-400 hover:text-zinc-600"
        >
          Delete
        </button>
      )}
      {error && <span className="text-bw-xs text-bite-dark">{error}</span>}
    </div>
  );
}

/** E11 — inline edit form for the author's own review (rating + body). */
function EditReviewForm({
  review,
  onCancel,
  onSaved,
}: {
  review: ReviewPayload;
  onCancel: () => void;
  onSaved: (saved: ReviewPayload) => void;
}) {
  const [rating, setRating] = useState(review.rating);
  const [body, setBody] = useState(review.body ?? '');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      const saved = await updateReview(review.id, { rating, body: body.trim() || null });
      onSaved(saved);
    } catch (e) {
      setError((e as Error).message);
      setSaving(false);
    }
  };

  return (
    <form onSubmit={submit} data-testid={`edit-form-${review.id}`}>
      <div className="flex items-center gap-1">
        {[1, 2, 3, 4, 5].map((n) => (
          <button
            type="button"
            key={n}
            onClick={() => setRating(n)}
            data-testid={`edit-star-${review.id}-${n}`}
            aria-pressed={rating >= n}
            className={['text-2xl', rating >= n ? 'text-bite' : 'text-zinc-300'].join(' ')}
          >
            ★
          </button>
        ))}
      </div>
      <textarea
        value={body}
        onChange={(e) => setBody(e.target.value)}
        aria-label={`edit-body-${review.id}`}
        rows={3}
        className="mt-bw-2 w-full rounded-bw-md border border-zinc-300 p-bw-2 text-bw-base"
      />
      {error && (
        <p className="mt-bw-2 rounded-bw-md bg-bite-light px-bw-2 py-bw-1 text-bw-xs text-bite-dark">
          {error}
        </p>
      )}
      <div className="mt-bw-2 flex items-center justify-end gap-bw-2">
        <button
          type="button"
          onClick={onCancel}
          className="text-bw-sm font-semibold text-zinc-500 hover:text-zinc-700"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={saving}
          data-testid={`save-edit-${review.id}`}
          className={[
            'rounded-bw-md bg-bite px-bw-3 py-bw-1 text-bw-sm font-bold text-white',
            saving ? 'opacity-60' : 'hover:bg-bite-dark',
          ].join(' ')}
        >
          {saving ? 'Saving…' : 'Save'}
        </button>
      </div>
    </form>
  );
}

/**
 * Legal remediation E8 — "Report" affordance. Routes the review into
 * the moderation queue (the same queue the spam heuristic feeds).
 * Signed-in only; a 401 nudges the reader to sign in.
 */
function ReportControl({ reviewId }: { reviewId: string }) {
  const [state, setState] = useState<'idle' | 'sending' | 'done' | 'signin' | 'error'>('idle');

  if (state === 'done') {
    return <p className="mt-1 text-bw-xs text-zinc-500" data-testid={`reported-${reviewId}`}>Reported — thanks. A moderator will take a look.</p>;
  }

  const onReport = async () => {
    setState('sending');
    try {
      await reportReview(reviewId);
      setState('done');
    } catch (e) {
      setState(e instanceof ReviewError && e.status === 401 ? 'signin' : 'error');
    }
  };

  return (
    <div className="mt-1">
      <button
        type="button"
        onClick={onReport}
        disabled={state === 'sending'}
        data-testid={`report-${reviewId}`}
        className="text-bw-xs font-semibold text-zinc-400 hover:text-zinc-600"
      >
        {state === 'sending' ? 'Reporting…' : 'Report'}
      </button>
      {state === 'signin' && (
        <span className="ml-2 text-bw-xs text-zinc-500">Sign in to report.</span>
      )}
      {state === 'error' && (
        <span className="ml-2 text-bw-xs text-bite-dark">Couldn’t report — try again.</span>
      )}
    </div>
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
