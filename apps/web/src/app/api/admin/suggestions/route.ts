/**
 * `GET /api/admin/suggestions` → the cross-restaurant queue; filters
 * pass through untouched, adminProxy stamps no-store.
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../lib/api-proxy';

export async function GET(request: NextRequest) {
  return adminProxy(`/api/v1/admin/suggestions${request.nextUrl.search ?? ''}`);
}
