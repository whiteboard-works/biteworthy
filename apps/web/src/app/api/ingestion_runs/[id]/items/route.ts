/**
 * Phase 6.5 — `GET /api/ingestion_runs/:id/items` proxies the staged
 * item list for the web verify page (creator-or-admin per Phase 6.3).
 * `no-store` so the verify page always sees fresh staging state.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../../../lib/api-proxy';

export async function GET(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return proxyAuthed(`/api/v1/ingestion_runs/${encodeURIComponent(id)}/items`, {
    cache: 'no-store',
  });
}
