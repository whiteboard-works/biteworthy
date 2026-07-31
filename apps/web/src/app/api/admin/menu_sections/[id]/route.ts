/**
 * `PATCH/DELETE /api/admin/menu_sections/:id`. Delete responds with the
 * count of items left unsectioned — they are never deleted.
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../lib/api-proxy';

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/menu_sections/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    body: await request.text(),
  });
}

export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/menu_sections/${encodeURIComponent(id)}`, { method: 'DELETE' });
}
