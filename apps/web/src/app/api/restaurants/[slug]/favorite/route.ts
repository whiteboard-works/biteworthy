/**
 * Proxy POST/DELETE /api/restaurants/:slug/favorite to Rails with the
 * bw_session cookie's JWT. Save/unsave a restaurant for the current
 * user. The API accepts the slug or UUID interchangeably.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../../../lib/api-proxy';

export async function POST(_request: NextRequest, context: { params: Promise<{ slug: string }> }) {
  const { slug } = await context.params;
  return proxyAuthed(`/api/v1/restaurants/${encodeURIComponent(slug)}/favorite`, { method: 'POST' });
}

export async function DELETE(_request: NextRequest, context: { params: Promise<{ slug: string }> }) {
  const { slug } = await context.params;
  return proxyAuthed(`/api/v1/restaurants/${encodeURIComponent(slug)}/favorite`, {
    method: 'DELETE',
  });
}
