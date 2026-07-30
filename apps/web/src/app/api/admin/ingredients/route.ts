/**
 * `GET/POST /api/admin/ingredients` → the taxonomy list + create.
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../lib/api-proxy';

export async function GET(request: NextRequest) {
  return adminProxy(`/api/v1/admin/ingredients${request.nextUrl.search ?? ''}`);
}

export async function POST(request: NextRequest) {
  return adminProxy('/api/v1/admin/ingredients', { method: 'POST', body: await request.text() });
}
