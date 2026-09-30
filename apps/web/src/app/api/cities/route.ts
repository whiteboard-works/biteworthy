/**
 * Proxy GET /api/cities to Rails.
 *
 * Anonymous-allowed, like the endpoint it fronts: the list is public.
 * It exists so a browser-side page (the settings Home city picker) calls
 * the API same-origin like every other client call, with the visitor's
 * own edge headers — rather than cross-origin straight at Rails, which
 * would depend on CORS and be throttled as the Next server.
 */
import { NextResponse } from 'next/server';
import { API_BASE } from '../../../lib/api-base';
import { edgeHeaders } from '../../../lib/edge-headers';

export async function GET() {
  const upstream = await fetch(`${API_BASE}/api/v1/cities`, {
    headers: { Accept: 'application/json', ...(await edgeHeaders()) },
    cache: 'no-store',
  });
  const text = await upstream.text();
  return new NextResponse(text, {
    status: upstream.status,
    headers: {
      'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json',
      'Cache-Control': 'private, no-store',
    },
  });
}
