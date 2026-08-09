/**
 * Proxy GET /api/restaurants/:slug/items to Rails.
 *
 * Anonymous-allowed, like the Rails endpoint it fronts — browsing a menu
 * never requires an account. But when the cookie carries a JWT it has to
 * be forwarded, because the menu is *filtered by who is asking*: the
 * caller's avoid lists, their strictness, their never-hide overrides, and
 * their taste scores all come from that header.
 *
 * The browser cannot call Rails directly for this. `bw_session` is
 * HttpOnly and owned by the web origin, so a cross-origin fetch to the
 * API carries no credential at all — which is exactly how the client
 * refetch came to silently drop the signed-in user's profile on every
 * strictness toggle.
 */
import { NextResponse, type NextRequest } from 'next/server';
import { API_BASE } from '../../../../../lib/api-base';
import { getServerJwt } from '../../../../../lib/server-auth';

/** The only params Rails reads; anything else is dropped rather than relayed. */
const FORWARDED_PARAMS = ['profile_token', 'profile', 'strictness'] as const;

export async function GET(
  request: NextRequest,
  context: { params: Promise<{ slug: string }> },
) {
  const { slug } = await context.params;

  const params = new URLSearchParams();
  for (const key of FORWARDED_PARAMS) {
    const value = request.nextUrl.searchParams.get(key);
    if (value) params.set(key, value);
  }
  const qs = params.toString();

  const headers: Record<string, string> = { Accept: 'application/json' };
  const jwt = await getServerJwt();
  if (jwt) headers.Authorization = `Bearer ${jwt}`;

  const upstream = await fetch(
    `${API_BASE}/api/v1/restaurants/${encodeURIComponent(slug)}/items${qs ? `?${qs}` : ''}`,
    { headers },
  );
  const text = await upstream.text();
  return new NextResponse(text, {
    status: upstream.status,
    headers: {
      'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json',
      // The response depends on the caller's cookie. Without this a shared
      // cache could hand one user's filtered menu to another.
      'Cache-Control': 'private, no-store',
    },
  });
}
