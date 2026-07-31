/**
 * `GET/PATCH /api/admin/restaurants/:id` — detail + edit (immutable
 * slug 422s relay verbatim).
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../lib/api-proxy';

export async function GET(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/restaurants/${encodeURIComponent(id)}`);
}

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/restaurants/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    body: await request.text(),
  });
}
