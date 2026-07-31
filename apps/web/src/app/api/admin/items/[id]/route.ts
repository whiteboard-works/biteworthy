/**
 * `PATCH /api/admin/items/:id` — name/description/status only
 * (status: removed = unpublish).
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../lib/api-proxy';

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/items/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    body: await request.text(),
  });
}
