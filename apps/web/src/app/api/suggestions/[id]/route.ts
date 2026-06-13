/**
 * Phase 4.10 — proxy PATCH /api/suggestions/:id (owner accept/reject)
 * with the cookie's JWT.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../../lib/api-proxy';

export async function PATCH(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return proxyAuthed(`/api/v1/suggestions/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    body: await request.text(),
  });
}
