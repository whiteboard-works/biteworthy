/**
 * Read + write helpers for the account page's dietary preferences.
 *
 * Both go through the Next `/api/profile` proxy (not the direct `api`
 * helper), so the HttpOnly `bw_session` JWT is attached server-side
 * and never reaches JS — same path as `saveProfile` in `./onboarding`.
 *
 * `updateProfile` sends a PARTIAL patch: the Rails endpoint only
 * replaces the arrays present in the body, so changing strictness or
 * one avoid list never touches the others. Each array it DOES send is
 * replaced wholesale, so callers pass the full canonical array (built
 * from the current profile loaded via `fetchProfile`).
 */
import type { ProfilePayload } from '@biteworthy/api-types';
import type { Strictness } from '@biteworthy/filter-engine';
import type { UserReviewItem } from './users';

export type { ProfilePayload };

/** The fields the account page can patch. All optional; omit to leave untouched. */
export interface ProfilePatch {
  strictness?: Strictness;
  /**
   * Wholesale replacement. Right for the onboarding wizard, which just
   * built the list in front of the person — what it sends *is* the answer.
   *
   * Wrong for a page that edits one chip at a time: the array is rebuilt
   * from whatever loaded at mount, and between that load and the click the
   * chat or an MCP client may have added an allergen, which replacement
   * then silently removes. Use the add_/remove_ pair for incremental
   * edits. Sending both forms for one list is a 422.
   */
  avoid_ingredient_ids?: string[];
  avoid_tag_ids?: string[];
  add_avoid_ingredient_ids?: string[];
  remove_avoid_ingredient_ids?: string[];
  add_avoid_tag_ids?: string[];
  remove_avoid_tag_ids?: string[];
  prefer_tag_ids?: string[];
  liked_ingredient_ids?: string[];
  liked_tag_ids?: string[];
  disliked_ingredient_ids?: string[];
  disliked_tag_ids?: string[];
  /** Additive — unions the preset's avoid lists onto the stored ones. */
  dietary_profile_slug?: string;
}

/** Raised on a 401 so callers can bounce to /login. */
export class NotSignedInError extends Error {
  constructor() {
    super('not signed in');
    this.name = 'NotSignedInError';
  }
}

async function readJsonOrThrow<T>(res: Response, action: string): Promise<T> {
  if (res.status === 401) throw new NotSignedInError();
  if (!res.ok) {
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      // ignore — non-JSON error body
    }
    throw new Error(`${action} failed: ${res.status} ${JSON.stringify(body)}`);
  }
  return (await res.json()) as T;
}

export async function fetchProfile(
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<ProfilePayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl('/api/profile', {
    credentials: 'same-origin',
    headers: { Accept: 'application/json' },
  });
  return readJsonOrThrow<ProfilePayload>(res, 'fetchProfile');
}

export async function updateProfile(
  patch: ProfilePatch,
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<ProfilePayload> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl('/api/profile', {
    method: 'PATCH',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(patch),
  });
  return readJsonOrThrow<ProfilePayload>(res, 'updateProfile');
}

// ─── My reviews (account page) ────────────────────────────────────

/**
 * A row from GET /api/profile/reviews — the caller's own review. The
 * item shape is the public `UserReviewItem` plus `status`, which the
 * account page uses to skip the link for a dish that's no longer
 * viewable (the public item page is published-only).
 */
export interface MyReview {
  id: string;
  item: UserReviewItem & { status: string };
  rating: number;
  body: string | null;
  photo_url: string | null;
  /** True when a moderator hid it; the author still sees it here. */
  hidden: boolean;
  hidden_reason: string | null;
  created_at: string;
  updated_at: string;
}

export interface MyReviewsResponse {
  reviews: MyReview[];
  total: number;
}

export async function fetchMyReviews(
  opts: { limit?: number; offset?: number; fetchImpl?: typeof fetch } = {},
): Promise<MyReviewsResponse> {
  const { fetchImpl = fetch, limit, offset } = opts;
  const url = new URL('/api/profile/reviews', 'http://placeholder');
  if (typeof limit === 'number') url.searchParams.set('limit', String(limit));
  if (typeof offset === 'number') url.searchParams.set('offset', String(offset));
  const res = await fetchImpl(`${url.pathname}${url.search}`, {
    credentials: 'same-origin',
    headers: { Accept: 'application/json' },
  });
  return readJsonOrThrow<MyReviewsResponse>(res, 'fetchMyReviews');
}

// ─── Favorites (account page) ─────────────────────────────────────

export interface FavoriteRestaurant {
  id: string;
  slug: string;
  name: string;
  status: string;
}

export interface FavoriteDish {
  id: string;
  name: string;
  status: string;
  // `restaurant.status` matters too: a dish stays 'published' when its
  // restaurant is later closed, but the dish page resolves through the
  // restaurant, so the link is only safe when both are published.
  restaurant: { id: string; slug: string; name: string; status: string };
}

export interface MyFavoritesResponse {
  restaurants: FavoriteRestaurant[];
  items: FavoriteDish[];
}

export async function fetchMyFavorites(
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<MyFavoritesResponse> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl('/api/profile/favorites', {
    credentials: 'same-origin',
    headers: { Accept: 'application/json' },
  });
  return readJsonOrThrow<MyFavoritesResponse>(res, 'fetchMyFavorites');
}
