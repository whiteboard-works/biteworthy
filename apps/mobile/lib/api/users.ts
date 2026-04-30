/**
 * Phase 4.7 — public user profile fetcher (mobile).
 *
 * Anonymous endpoint, no JWT needed. Mirrors apps/web/src/lib/users.ts.
 */
const API_BASE = process.env.EXPO_PUBLIC_API_BASE ?? 'http://localhost:3000';

export interface UserReviewItem {
  id: string;
  name: string;
  restaurant: { id: string; slug: string; name: string };
}

export interface UserReview {
  id: string;
  item: UserReviewItem;
  rating: number;
  body: string | null;
  photo_url: string | null;
  created_at: string;
}

export interface PublicUserProfile {
  handle: string;
  display_name: string | null;
  member_since: string;
  reviews_count: number;
  restaurants_reviewed_count: number;
  recent_reviews: UserReview[];
}

export class UserProfileFetchError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'UserProfileFetchError';
  }
}

export interface FetchOptions {
  fetchImpl?: typeof fetch;
}

export async function fetchPublicUserProfile(
  handle: string,
  opts: FetchOptions = {},
): Promise<PublicUserProfile | null> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`${API_BASE}/api/v1/users/${encodeURIComponent(handle)}`);
  if (res.status === 404) return null;
  if (!res.ok) throw new UserProfileFetchError(res.status, `fetchPublicUserProfile ${handle} failed: ${res.status}`);
  return (await res.json()) as PublicUserProfile;
}
