/**
 * `POST /api/admin/reviews/:id/hide` — forwards `{ reason }`; Rails
 * 422s unknown reasons (relayed verbatim).
 */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../../lib/api-proxy';

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/reviews/${encodeURIComponent(id)}/hide`, {
    method: 'POST',
    body: await request.text(),
  });
}
