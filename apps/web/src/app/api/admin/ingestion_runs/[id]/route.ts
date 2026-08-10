/**
 * `DELETE /api/admin/ingestion_runs/:id` — archive, or destroy with
 * `?hard=true` (Rails 404s a non-super admin).
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../lib/api-proxy';

// `hard=true` is forwarded explicitly rather than relaying the whole
// query string: it is the one parameter this endpoint takes, and a
// blanket forward would hand arbitrary caller-controlled params to an
// admin route for no benefit.
function hardSuffix(request: NextRequest): string {
  return request.nextUrl.searchParams.get('hard') === 'true' ? '?hard=true' : '';
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  return adminProxy(
    `/api/v1/admin/ingestion_runs/${encodeURIComponent(id)}${hardSuffix(request)}`,
    { method: 'DELETE' },
  );
}
