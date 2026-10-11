/**
 * Admin diner dish-photo queue. Types come from the generated OpenAPI
 * client after rswag export — a missing field here is a contract break.
 */
import type { paths } from '@biteworthy/api-types';
import { getAdminJson, postAdminJson } from './shared';

export type AdminPhotoSubmissionsResponse =
  paths['/api/v1/admin/photo_submissions']['get']['responses']['200']['content']['application/json'];
export type AdminPhotoSubmissionRow = AdminPhotoSubmissionsResponse['photo_submissions'][number];

export const PHOTO_STATUSES = ['pending', 'approved', 'rejected', 'all'] as const;
export type PhotoQueueStatus = (typeof PHOTO_STATUSES)[number];

export const REJECT_REASONS = [
  'not_this_dish',
  'low_quality',
  'inappropriate',
  'not_food',
  'duplicate',
] as const;
export type PhotoRejectReason = (typeof REJECT_REASONS)[number];

export function fetchPhotoSubmissions(
  query: { status?: PhotoQueueStatus; limit?: number; offset?: number } = {},
  fetchImpl?: typeof fetch,
): Promise<AdminPhotoSubmissionsResponse> {
  const params = new URLSearchParams();
  if (query.status) params.set('status', query.status);
  if (query.limit != null) params.set('limit', String(query.limit));
  if (query.offset != null) params.set('offset', String(query.offset));
  const qs = params.toString();
  return getAdminJson<AdminPhotoSubmissionsResponse>(
    `/api/admin/photo_submissions${qs ? `?${qs}` : ''}`,
    fetchImpl,
  );
}

export function approvePhotoSubmission(
  id: string,
  replaceItemPhoto: boolean,
  fetchImpl?: typeof fetch,
): Promise<AdminPhotoSubmissionRow> {
  return postAdminJson(
    `/api/admin/photo_submissions/${encodeURIComponent(id)}/approve`,
    { body: { replace_item_photo: replaceItemPhoto } },
    fetchImpl,
  );
}

export function rejectPhotoSubmission(
  id: string,
  reason: PhotoRejectReason,
  fetchImpl?: typeof fetch,
): Promise<AdminPhotoSubmissionRow> {
  return postAdminJson(
    `/api/admin/photo_submissions/${encodeURIComponent(id)}/reject`,
    { body: { reason } },
    fetchImpl,
  );
}
