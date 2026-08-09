import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../../lib/api-proxy';

export async function DELETE(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return proxyAuthed(`/api/v1/connected_apps/${encodeURIComponent(id)}`, { method: 'DELETE' });
}
