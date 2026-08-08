/**
 * The caller's chat conversations. `no-store` — a stale list would show
 * a conversation that has since been renamed by its first message.
 */
import { proxyAuthed } from '../../../../lib/api-proxy';

export async function GET() {
  return proxyAuthed('/api/v1/conversations', { cache: 'no-store' });
}

export async function POST() {
  return proxyAuthed('/api/v1/conversations', { method: 'POST', body: '{}' });
}
