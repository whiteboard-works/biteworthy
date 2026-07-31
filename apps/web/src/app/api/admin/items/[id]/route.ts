/**
 * `PATCH /api/admin/items/:id` — the deep edit: name, description,
 * status (removed = unpublish), section, ingredient/tag slugs, variants
 * and modifiers. The body is forwarded as-is; the server decides what
 * it permits.
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
