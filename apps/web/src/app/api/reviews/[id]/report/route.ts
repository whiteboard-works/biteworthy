/**
 * Legal remediation E8 — proxy POST /api/reviews/:id/report to Rails
 * with the cookie's JWT. Routes the review into the moderation queue.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../../../lib/server-auth';

import { API_BASE } from '../../../../../lib/api-base';

export async function POST(
  _request: NextRequest,
  context: { params: Promise<{ id: string }> },
) {
  const { id } = await context.params;
  const jwt = await getServerJwt();
  if (!jwt) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 });
  }

  const upstream = await fetch(
    `${API_BASE}/api/v1/reviews/${encodeURIComponent(id)}/report`,
    { method: 'POST', headers: { Authorization: `Bearer ${jwt}` } },
  );
  const text = await upstream.text();
  return new NextResponse(text.length > 0 ? text : null, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}
