/**
 * `GET /api/admin/ingestion_runs` → the cross-user moderation queue.
 * Filters (status/community/restaurant_id/limit/offset) pass through
 * untouched; adminProxy stamps no-store.
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../lib/api-proxy';

export async function GET(request: NextRequest) {
  return adminProxy(`/api/v1/admin/ingestion_runs${request.nextUrl.search ?? ''}`);
}
