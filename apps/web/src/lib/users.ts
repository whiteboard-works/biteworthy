/**
 * Phase 4.7 — public user profile fetcher.
 *
 * Anonymous endpoint (no auth header), so this is safe to call from
 * SSR pages without `getServerJwt`.
 */
import { api, type ApiOptions } from './api';

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

export class UserProfileNotFoundError extends Error {
  constructor(handle: string) {
    super(`User profile not found: ${handle}`);
    this.name = 'UserProfileNotFoundError';
  }
}

export async function fetchPublicUserProfile(
  handle: string,
  opts: ApiOptions = {},
): Promise<PublicUserProfile | null> {
  try {
    return await api<PublicUserProfile>(`/users/${encodeURIComponent(handle)}`, opts);
  } catch (e) {
    // The api() helper throws on non-2xx with a message containing
    // the status. Surface 404 as null so SSR can call notFound().
    if ((e as Error).message.includes('404')) return null;
    throw e;
  }
}
