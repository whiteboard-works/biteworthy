/** `GET/POST /api/admin/restaurants/:id/menus` — the menu tree. */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../../lib/api-proxy';

export async function GET(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/restaurants/${encodeURIComponent(id)}/menus`);
}

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/restaurants/${encodeURIComponent(id)}/menus`, {
    method: 'POST',
    body: await request.text(),
  });
}
