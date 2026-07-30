/**
 * `PATCH/DELETE /api/admin/ingredients/:id` — update (immutable
 * slug/path 422s relay verbatim) and delete (409 in_use relays with
 * its reference counts).
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../lib/api-proxy';

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/ingredients/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    body: await request.text(),
  });
}

export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/ingredients/${encodeURIComponent(id)}`, { method: 'DELETE' });
}
