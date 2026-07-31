/**
 * `GET /api/admin/users` — list/search (admin-only surface; emails).
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../lib/api-proxy';

export async function GET(request: NextRequest) {
  return adminProxy(`/api/v1/admin/users${request.nextUrl.search ?? ''}`);
}
