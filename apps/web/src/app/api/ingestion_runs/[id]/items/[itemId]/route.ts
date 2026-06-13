/**
 * Phase 6.5 — `PATCH /api/ingestion_runs/:id/items/:itemId` proxies
 * accept / reject / edit decisions from the web verify page.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../../../../lib/api-proxy';

export async function PATCH(
  request: NextRequest,
  context: { params: Promise<{ id: string; itemId: string }> },
) {
  const { id, itemId } = await context.params;
  return proxyAuthed(
    `/api/v1/ingestion_runs/${encodeURIComponent(id)}/items/${encodeURIComponent(itemId)}`,
    { method: 'PATCH', body: await request.text() },
  );
}
