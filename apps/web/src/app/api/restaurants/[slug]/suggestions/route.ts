/**
 * Phase 4.10 — proxy GET /api/restaurants/:slug/suggestions
 * (owner-only queue) with the cookie's JWT.
 */
import { proxyAuthed } from '../../../../../lib/api-proxy';

export async function GET(_request: Request, context: { params: Promise<{ slug: string }> }) {
  const { slug } = await context.params;
  return proxyAuthed(`/api/v1/restaurants/${encodeURIComponent(slug)}/suggestions`);
}
