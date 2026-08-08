/**
 * One conversation's transcript, and deleting it. GET is the reconnect
 * path — a dropped stream loses nothing because the turn was persisted
 * as it ran.
 */
import { proxyAuthed } from '../../../../../lib/api-proxy';

export async function GET(_request: Request, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return proxyAuthed(`/api/v1/conversations/${encodeURIComponent(id)}`, { cache: 'no-store' });
}

export async function DELETE(_request: Request, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return proxyAuthed(`/api/v1/conversations/${encodeURIComponent(id)}`, { method: 'DELETE' });
}
