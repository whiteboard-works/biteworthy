/**
 * Phase 4.5 — web review API client.
 *
 * Mirrors the mobile client at apps/mobile/lib/api/reviews.ts but
 * routes through the Next proxy at /api/items/:id/reviews and
 * /api/reviews/:id, which inject the bw_session cookie's JWT as a
 * Bearer header. The browser never touches the JWT directly.
 *
 * SSR pages can call `fetchReviewsServer` directly against Rails (no
 * auth needed for the public index endpoint).
 */
import { api, type ApiOptions } from './api';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';

export interface ReviewAuthor {
  id: string;
  handle: string | null;
  display_name: string | null;
}

export interface ReviewPayload {
  id: string;
  item_id: string;
  user: ReviewAuthor;
  rating: number;
  body: string | null;
  photo_url: string | null;
  created_at: string;
  updated_at: string;
}

export interface ReviewsResponse {
  item_id: string;
  reviews: ReviewPayload[];
  total: number;
}

export class ReviewError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ReviewError';
  }
}

export interface PaginationOptions {
  limit?: number;
  offset?: number;
  fetchImpl?: typeof fetch;
}

/**
 * Anonymous browser fetch via the Next proxy. Use this from client
 * components.
 */
export async function fetchReviews(
  itemId: string,
  opts: PaginationOptions = {},
): Promise<ReviewsResponse> {
  const { fetchImpl = fetch, limit, offset } = opts;
  const url = new URL(`/api/items/${encodeURIComponent(itemId)}/reviews`, 'http://placeholder');
  if (typeof limit === 'number') url.searchParams.set('limit', String(limit));
  if (typeof offset === 'number') url.searchParams.set('offset', String(offset));
  const path = `${url.pathname}${url.search}`;
  const res = await fetchImpl(path, { credentials: 'same-origin' });
  if (!res.ok) throw new ReviewError(res.status, `fetchReviews ${itemId} failed: ${res.status}`);
  return (await res.json()) as ReviewsResponse;
}

/**
 * Server-side fetch (SSR). Hits Rails directly — no cookie / proxy
 * needed since the index endpoint is public.
 */
export async function fetchReviewsServer(itemId: string): Promise<ReviewsResponse> {
  return api<ReviewsResponse>(`/items/${encodeURIComponent(itemId)}/reviews`);
}

export interface NewReview {
  rating: number;
  body?: string;
  /**
   * Browser File from an <input type="file"> picker. Sends multipart;
   * omit for text-only reviews (sends JSON).
   */
  photo?: File | null;
}

export async function createReview(
  itemId: string,
  review: NewReview,
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<ReviewPayload> {
  const { fetchImpl = fetch } = opts;
  const path = `/api/items/${encodeURIComponent(itemId)}/reviews`;
  let body: BodyInit;
  const headers: Record<string, string> = {};
  if (review.photo) {
    const form = new FormData();
    form.append('rating', String(review.rating));
    if (review.body != null) form.append('body', review.body);
    form.append('photo', review.photo, review.photo.name);
    body = form;
    // No Content-Type — fetch sets the multipart boundary.
  } else {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify({ rating: review.rating, body: review.body });
  }
  const res = await fetchImpl(path, {
    method: 'POST',
    credentials: 'same-origin',
    headers,
    body,
  });
  if (!res.ok) throw await reviewError(res, `createReview ${itemId}`);
  return (await res.json()) as ReviewPayload;
}

export interface UpdateReview {
  rating?: number;
  body?: string | null;
}

export async function updateReview(
  reviewId: string,
  patch: UpdateReview,
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<ReviewPayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`/api/reviews/${encodeURIComponent(reviewId)}`, {
    method: 'PATCH',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(patch),
  });
  if (!res.ok) throw await reviewError(res, `updateReview ${reviewId}`);
  return (await res.json()) as ReviewPayload;
}

export async function deleteReview(
  reviewId: string,
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<void> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`/api/reviews/${encodeURIComponent(reviewId)}`, {
    method: 'DELETE',
    credentials: 'same-origin',
  });
  if (!res.ok) throw await reviewError(res, `deleteReview ${reviewId}`);
}

async function reviewError(res: Response, label: string): Promise<ReviewError> {
  let body: { error?: string } | null = null;
  try {
    body = (await res.json()) as { error?: string };
  } catch {
    // ignore
  }
  return new ReviewError(res.status, `${label} failed: ${res.status}${body?.error ? ` — ${body.error}` : ''}`);
}

// Re-export to keep imports from screens tidy.
export { type ApiOptions };
export { API_BASE };
