/**
 * The consent screen's data, proxied with the session JWT.
 *
 * The screen renders here rather than in Rails because this is the only
 * origin where a browser is signed in — the JWT lives in the HttpOnly
 * `bw_session` cookie, which Rails never receives. See
 * apps/api/config/initializers/doorkeeper.rb for the full handoff.
 *
 * Nothing here decides anything. Rails validates the client, the scopes,
 * the redirect URI, and the requested audience; this route only carries
 * the answer.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../../lib/api-proxy';

export async function GET(request: NextRequest) {
  const returnTo = request.nextUrl.searchParams.get('return_to') ?? '';
  return proxyAuthed(`/api/v1/oauth/consent?return_to=${encodeURIComponent(returnTo)}`, {
    cache: 'no-store',
  });
}

export async function POST(request: NextRequest) {
  return proxyAuthed('/api/v1/oauth/consent', { method: 'POST', body: await request.text() });
}
