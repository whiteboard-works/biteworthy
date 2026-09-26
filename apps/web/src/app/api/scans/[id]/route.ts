/** One scan's progress, and its dishes once ready. Polled, so never cached. */
import { proxyAuthed } from '../../../../lib/api-proxy';

export async function GET(_request: Request, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return proxyAuthed(`/api/v1/scans/${encodeURIComponent(id)}`, { cache: 'no-store' });
}
