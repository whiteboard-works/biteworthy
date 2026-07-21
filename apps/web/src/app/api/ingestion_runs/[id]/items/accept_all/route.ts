/**
 * `POST /api/ingestion_runs/:id/items/accept_all` — proxies the verify
 * page's "Accept All" to Rails (bulk-accept every pending item).
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../../../../lib/api-proxy';

export async function POST(
  _request: NextRequest,
  context: { params: Promise<{ id: string }> },
) {
  const { id } = await context.params;
  return proxyAuthed(`/api/v1/ingestion_runs/${encodeURIComponent(id)}/items/accept_all`, {
    method: 'POST',
  });
}
