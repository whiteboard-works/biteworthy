/** Publishes the dishes the person ticked to the live menu. */
import { proxyAuthed } from '../../../../../lib/api-proxy';

export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return proxyAuthed(`/api/v1/scans/${encodeURIComponent(id)}/accept`, {
    method: 'POST',
    body: await request.text(),
  });
}
