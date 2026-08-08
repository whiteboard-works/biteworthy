/**
 * Least-privilege credentials for MCP clients.
 *
 * The secret comes back exactly once, on create — nothing stored can
 * reproduce it, so there is no route here that could return it again.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../lib/api-proxy';

export async function GET() {
  return proxyAuthed('/api/v1/mcp_tokens');
}

export async function POST(request: NextRequest) {
  return proxyAuthed('/api/v1/mcp_tokens', { method: 'POST', body: await request.text() });
}
