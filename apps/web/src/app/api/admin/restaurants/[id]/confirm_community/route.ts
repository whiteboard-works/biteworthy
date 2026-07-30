/**
 * `POST /api/admin/restaurants/:id/confirm_community` — the strict-mode
 * graduation lever; relays the flipped-row counts.
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../../lib/api-proxy';

export async function POST(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/restaurants/${encodeURIComponent(id)}/confirm_community`, {
    method: 'POST',
  });
}
