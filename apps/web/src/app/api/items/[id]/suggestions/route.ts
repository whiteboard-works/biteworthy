/**
 * Phase 4.10 — proxy POST /api/items/:id/suggestions to Rails.
 * Anonymous-allowed: no JWT required to suggest a fix. If the
 * cookie carries one, forward it so the suggestion attributes
 * properly.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { getServerJwt } from '../../../../../lib/server-auth';

import { API_BASE } from '../../../../../lib/api-base';

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ id: string }> },
) {
  const { id } = await context.params;
  const body = await request.text();
  const jwt = await getServerJwt();

  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    Accept: 'application/json',
  };
  if (jwt) headers.Authorization = `Bearer ${jwt}`;

  const upstream = await fetch(
    `${API_BASE}/api/v1/items/${encodeURIComponent(id)}/suggestions`,
    { method: 'POST', headers, body },
  );
  const text = await upstream.text();
  return new NextResponse(text, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
  });
}
