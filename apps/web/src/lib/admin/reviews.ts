/**
 * Admin review moderation: the visibility queues plus hide/unhide.
 * Hide's reason becomes the user-facing "why was this hidden" copy,
 * so the picker is constrained to the server's HIDDEN_REASONS enum.
 */
import type { paths } from '@biteworthy/api-types';
import { getAdminJson, postAdminJson } from './shared';

export type AdminReviewsResponse =
  paths['/api/v1/admin/reviews']['get']['responses']['200']['content']['application/json'];
export type AdminReviewRow = AdminReviewsResponse['reviews'][number];

export const REVIEW_VISIBILITIES = ['flagged', 'hidden', 'visible', 'all'] as const;
export type ReviewVisibility = (typeof REVIEW_VISIBILITIES)[number];

export const HIDE_REASONS = ['spam', 'abuse', 'duplicate', 'off_topic'] as const;
export type HideReason = (typeof HIDE_REASONS)[number];

export function fetchModerationReviews(
  query: { visibility?: ReviewVisibility; limit?: number; offset?: number } = {},
  fetchImpl?: typeof fetch,
): Promise<AdminReviewsResponse> {
  const params = new URLSearchParams();
  if (query.visibility) params.set('visibility', query.visibility);
  if (query.limit != null) params.set('limit', String(query.limit));
  if (query.offset != null) params.set('offset', String(query.offset));
  const qs = params.toString();
  return getAdminJson<AdminReviewsResponse>(`/api/admin/reviews${qs ? `?${qs}` : ''}`, fetchImpl);
}

export function hideReview(
  reviewId: string,
  reason: HideReason,
  fetchImpl?: typeof fetch,
): Promise<AdminReviewRow> {
  return postAdminJson(
    `/api/admin/reviews/${encodeURIComponent(reviewId)}/hide`,
    { body: { reason } },
    fetchImpl,
  );
}

export function unhideReview(reviewId: string, fetchImpl?: typeof fetch): Promise<AdminReviewRow> {
  return postAdminJson(
    `/api/admin/reviews/${encodeURIComponent(reviewId)}/unhide`,
    {},
    fetchImpl,
  );
}
