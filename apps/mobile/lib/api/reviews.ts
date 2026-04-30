/**
 * Phase 4.4 — review API client (mobile).
 *
 * Mirrors the Phase 4.3 endpoints. fetchReviews is anonymous;
 * createReview / updateReview / deleteReview need a JWT (caller
 * passes it from the keychain via lib/auth.getJwt()).
 *
 * Photo upload uses multipart with the file URI from expo-camera.
 */

const API_BASE = process.env.EXPO_PUBLIC_API_BASE ?? 'http://localhost:3000';

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

export interface FetchOptions {
  fetchImpl?: typeof fetch;
}

export interface PaginationOptions extends FetchOptions {
  limit?: number;
  offset?: number;
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

export async function fetchReviews(
  itemId: string,
  opts: PaginationOptions = {},
): Promise<ReviewsResponse> {
  const { fetchImpl = fetch, limit, offset } = opts;
  const url = new URL(`${API_BASE}/api/v1/items/${encodeURIComponent(itemId)}/reviews`);
  if (typeof limit === 'number') url.searchParams.set('limit', String(limit));
  if (typeof offset === 'number') url.searchParams.set('offset', String(offset));
  const res = await fetchImpl(url.toString());
  if (!res.ok) throw new ReviewError(res.status, `fetchReviews ${itemId} failed: ${res.status}`);
  return (await res.json()) as ReviewsResponse;
}

export interface NewReview {
  rating: number;
  body?: string;
  /** Local file URI from expo-camera, or undefined to skip the photo. */
  photoUri?: string;
  /** Defaults to 'image/jpeg'. */
  photoMimeType?: string;
}

export async function createReview(
  itemId: string,
  jwt: string,
  review: NewReview,
  opts: FetchOptions = {},
): Promise<ReviewPayload> {
  const { fetchImpl = fetch } = opts;
  const headers: Record<string, string> = { Authorization: `Bearer ${jwt}` };
  let body: BodyInit;

  if (review.photoUri) {
    const form = new FormData();
    form.append('rating', String(review.rating));
    if (review.body != null) form.append('body', review.body);
    // RN's FormData accepts the {uri,name,type} blob shape — DOM
    // FormData wouldn't, but the runtime is RN here.
    form.append('photo', {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      uri: review.photoUri as any,
      name: filenameFromUri(review.photoUri),
      type: review.photoMimeType ?? 'image/jpeg',
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } as any);
    body = form;
    // Don't set Content-Type — fetch handles the multipart boundary.
  } else {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify({ rating: review.rating, body: review.body });
  }

  const res = await fetchImpl(`${API_BASE}/api/v1/items/${encodeURIComponent(itemId)}/reviews`, {
    method: 'POST',
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
  jwt: string,
  patch: UpdateReview,
  opts: FetchOptions = {},
): Promise<ReviewPayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/reviews/${encodeURIComponent(reviewId)}`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${jwt}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(patch),
  });
  if (!res.ok) throw await reviewError(res, `updateReview ${reviewId}`);
  return (await res.json()) as ReviewPayload;
}

export async function deleteReview(
  reviewId: string,
  jwt: string,
  opts: FetchOptions = {},
): Promise<void> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/reviews/${encodeURIComponent(reviewId)}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${jwt}` },
  });
  if (!res.ok) throw await reviewError(res, `deleteReview ${reviewId}`);
}

function filenameFromUri(uri: string): string {
  const last = uri.split('/').pop();
  return last && last.length > 0 ? last : 'photo.jpg';
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
