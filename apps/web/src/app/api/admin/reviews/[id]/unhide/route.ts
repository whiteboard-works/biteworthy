/**
 * `POST /api/admin/reviews/:id/unhide` — restores a hidden review.
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../../lib/api-proxy';

export async function POST(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/reviews/${encodeURIComponent(id)}/unhide`, { method: 'POST' });
}
