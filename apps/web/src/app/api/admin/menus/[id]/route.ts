/** `PATCH/DELETE /api/admin/menus/:id`. Deleting takes its sections; items survive. */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../lib/api-proxy';

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/menus/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    body: await request.text(),
  });
}

export async function DELETE(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/menus/${encodeURIComponent(id)}`, { method: 'DELETE' });
}
