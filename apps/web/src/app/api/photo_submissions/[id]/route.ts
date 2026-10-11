import { proxyAuthed } from '../../../../lib/api-proxy';

export async function DELETE(
  _request: Request,
  context: { params: Promise<{ id: string }> },
) {
  const { id } = await context.params;
  return proxyAuthed(`/api/v1/photo_submissions/${encodeURIComponent(id)}`, { method: 'DELETE' });
}
