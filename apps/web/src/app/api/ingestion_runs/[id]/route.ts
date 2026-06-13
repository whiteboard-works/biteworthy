/**
 * Phase 6.5 — `GET /api/ingestion_runs/:id` proxies run-status
 * polling for the web verify flow. `no-store` so polling isn't cached.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../../lib/api-proxy';

export async function GET(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return proxyAuthed(`/api/v1/ingestion_runs/${encodeURIComponent(id)}`, { cache: 'no-store' });
}
