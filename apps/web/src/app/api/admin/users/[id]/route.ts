/**
 * `PATCH /api/admin/users/:id` — the is_admin toggle (self-demotion
 * 422s relay verbatim).
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../lib/api-proxy';

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/users/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    body: await request.text(),
  });
}
