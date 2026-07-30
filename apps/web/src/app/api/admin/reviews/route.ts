/**
 * `GET /api/admin/reviews` → the moderation queue; filters pass
 * through untouched, adminProxy stamps no-store.
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../lib/api-proxy';

export async function GET(request: NextRequest) {
  return adminProxy(`/api/v1/admin/reviews${request.nextUrl.search ?? ''}`);
}
