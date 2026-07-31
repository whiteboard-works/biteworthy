/** `POST /api/admin/menus/:id/menu_sections` — add a sub-menu. */
import { type NextRequest } from 'next/server';
import { adminProxy } from '../../../../../../lib/api-proxy';

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return adminProxy(`/api/v1/admin/menus/${encodeURIComponent(id)}/menu_sections`, {
    method: 'POST',
    body: await request.text(),
  });
}
