/**
 * `POST /api/admin/cities` → add a city we cover.
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../lib/api-proxy';

export async function POST(request: NextRequest) {
  return adminProxy('/api/v1/admin/cities', { method: 'POST', body: await request.text() });
}
