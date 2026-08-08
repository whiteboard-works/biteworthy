/**
 * Uploads a menu photo or PDF and returns an id the chat can refer to,
 * so image bytes never enter the agent's context. Multipart, so the raw
 * body and its boundary are forwarded verbatim.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { API_BASE } from '../../../../lib/api-base';
import { relayUpstream } from '../../../../lib/api-proxy';
import { getServerJwt } from '../../../../lib/server-auth';

export async function POST(request: NextRequest) {
  const jwt = await getServerJwt();
  if (!jwt) return NextResponse.json({ error: 'Not signed in' }, { status: 401 });

  const contentType = request.headers.get('Content-Type');
  if (!contentType?.startsWith('multipart/form-data')) {
    return NextResponse.json({ error: 'Attach a file.' }, { status: 422 });
  }

  const upstream = await fetch(`${API_BASE}/api/v1/attachments`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': contentType },
    body: await request.arrayBuffer(),
  });
  return relayUpstream(upstream);
}
