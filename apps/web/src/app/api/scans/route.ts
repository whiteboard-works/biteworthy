/** Starts a menu scan through the Rails scan door. */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../lib/api-proxy';

export async function POST(request: NextRequest) {
  return proxyAuthed('/api/v1/scans', { method: 'POST', body: await request.text() });
}
