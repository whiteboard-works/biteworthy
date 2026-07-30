/**
 * `POST /api/admin/ingestion_runs/:id/re_extract` — rewinds a run and
 * re-fires extraction. Rails refuses published runs and runs holding
 * promoted items (422, relayed verbatim).
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../../lib/api-proxy';

export async function POST(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/ingestion_runs/${encodeURIComponent(id)}/re_extract`, {
    method: 'POST',
  });
}
