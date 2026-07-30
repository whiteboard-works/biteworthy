/**
 * `GET /api/admin/restaurants/:id/items` — all statuses, unlike the
 * public menu endpoint.
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../../lib/api-proxy';

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(
    `/api/v1/admin/restaurants/${encodeURIComponent(id)}/items${request.nextUrl.search ?? ''}`,
  );
}
