/**
 * Phase 4.9 — proxy POST /api/restaurants/:slug/claim (request a
 * claim verification email) with the cookie's JWT. The anonymous
 * token verification lives at .../claim/verify.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../../../lib/api-proxy';

export async function POST(request: NextRequest, context: { params: Promise<{ slug: string }> }) {
  const { slug } = await context.params;
  return proxyAuthed(`/api/v1/restaurants/${encodeURIComponent(slug)}/claim`, {
    method: 'POST',
    body: await request.text(),
  });
}
