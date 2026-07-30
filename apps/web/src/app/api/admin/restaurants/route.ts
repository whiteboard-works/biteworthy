/**
 * `GET /api/admin/restaurants` — list/search; filters pass through.
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../lib/api-proxy';

export async function GET(request: NextRequest) {
  return adminProxy(`/api/v1/admin/restaurants${request.nextUrl.search ?? ''}`);
}
