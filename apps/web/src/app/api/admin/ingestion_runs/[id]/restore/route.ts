/**
 * `POST /api/admin/ingestion_runs/:id/restore` — clears `archived_at`.
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../../lib/api-proxy';

export async function POST(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/ingestion_runs/${encodeURIComponent(id)}/restore`, {
    method: 'POST',
  });
}
