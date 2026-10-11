/**
 * POST /api/items/:id/photo_submissions → Rails multipart create.
 * Same shape as the review-photo proxy: forward the raw body + boundary
 * so the diner's JPEG reaches ActiveStorage intact.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../../../lib/server-auth';
import { API_BASE } from '../../../../../lib/api-base';
import { edgeHeaders } from '../../../../../lib/edge-headers';

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ id: string }> },
) {
  const { id } = await context.params;
  const jwt = await getServerJwt();
  if (!jwt) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  }

  const contentType = request.headers.get('Content-Type') ?? 'application/octet-stream';
  const headers: Record<string, string> = {
    Authorization: `Bearer ${jwt}`,
    'Content-Type': contentType,
    ...(await edgeHeaders()),
  };

  const upstream = await fetch(
    `${API_BASE}/api/v1/items/${encodeURIComponent(id)}/photo_submissions`,
    { method: 'POST', headers, body: await request.arrayBuffer() },
  );
  const responseText = await upstream.text();
  return new NextResponse(responseText, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}
