/** `GET /api/admin/restaurants/:id/place` — address + hours together. */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../../lib/api-proxy';

export async function GET(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/restaurants/${encodeURIComponent(id)}/place`);
}
