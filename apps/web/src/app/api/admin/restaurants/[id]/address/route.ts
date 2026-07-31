/** `PUT /api/admin/restaurants/:id/address` — create-or-replace. */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../../lib/api-proxy';

export async function PUT(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/restaurants/${encodeURIComponent(id)}/address`, {
    method: 'PUT',
    body: await request.text(),
  });
}
