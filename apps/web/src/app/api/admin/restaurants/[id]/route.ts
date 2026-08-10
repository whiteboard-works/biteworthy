/**
 * `GET/PATCH /api/admin/restaurants/:id` — detail + edit (immutable
 * slug 422s relay verbatim).
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../lib/api-proxy';

export async function GET(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/restaurants/${encodeURIComponent(id)}`);
}

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/restaurants/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    body: await request.text(),
  });
}

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
  return adminProxy(`/api/v1/admin/restaurants/${encodeURIComponent(id)}${hardSuffix(request)}`, {
    method: 'DELETE',
  });
}
