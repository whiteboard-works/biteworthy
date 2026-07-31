/**
 * `PUT /api/admin/restaurants/:id/hours` — the whole week at once. A
 * per-day write could land half-applied and advertise wrong hours.
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../../lib/api-proxy';

export async function PUT(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/restaurants/${encodeURIComponent(id)}/hours`, {
    method: 'PUT',
    body: await request.text(),
  });
}
