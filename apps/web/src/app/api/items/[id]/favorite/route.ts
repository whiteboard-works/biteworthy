/**
 * Proxy POST/DELETE /api/items/:id/favorite to Rails with the
 * bw_session cookie's JWT. Save/unsave a dish for the current user.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../../../lib/api-proxy';

export async function POST(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return proxyAuthed(`/api/v1/items/${encodeURIComponent(id)}/favorite`, { method: 'POST' });
}

export async function DELETE(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return proxyAuthed(`/api/v1/items/${encodeURIComponent(id)}/favorite`, { method: 'DELETE' });
}
