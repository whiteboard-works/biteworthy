/** The stop button. Raises a flag the running turn reads at its next
 *  checkpoint; it cannot be the same request as the turn, which is busy. */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../../../../lib/api-proxy';

export async function DELETE(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return proxyAuthed(`/api/v1/conversations/${encodeURIComponent(id)}/run`, { method: 'DELETE' });
}
