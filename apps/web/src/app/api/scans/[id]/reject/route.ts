/** Marks the dishes the person said aren't on the menu as rejected. */
import { proxyAuthed } from '../../../../../lib/api-proxy';

export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return proxyAuthed(`/api/v1/scans/${encodeURIComponent(id)}/reject`, {
    method: 'POST',
    body: await request.text(),
  });
}
