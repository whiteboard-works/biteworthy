/**
 * `PATCH /api/restaurants/:slug/branding` — relays the multipart logo /
 * banner upload to Rails with the cookie's JWT as Bearer. Serves both
 * the owner's control on the restaurant page and the admin workbench;
 * Rails decides who may (verified owner or admin). Same shape as the
 * reviews POST proxy.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../../../lib/server-auth';
import { API_BASE } from '../../../../../lib/api-base';
import { edgeHeaders } from '../../../../../lib/edge-headers';

export async function PATCH(request: NextRequest, context: { params: Promise<{ slug: string }> }) {
  const { slug } = await context.params;
  const jwt = await getServerJwt();
  if (!jwt) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  }

  const contentType = request.headers.get('Content-Type') ?? 'application/octet-stream';
  const upstream = await fetch(
    `${API_BASE}/api/v1/restaurants/${encodeURIComponent(slug)}/branding`,
    {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${jwt}`,
        Accept: 'application/json',
        'Content-Type': contentType,
        ...(await edgeHeaders()),
      },
      body: await request.arrayBuffer(),
    },
  );
  const responseText = await upstream.text();
  const response = new NextResponse(responseText, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
  response.headers.set('Cache-Control', 'no-store');
  return response;
}
