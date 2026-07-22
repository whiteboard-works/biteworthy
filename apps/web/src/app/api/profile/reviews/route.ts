/**
 * Proxy GET /api/profile/reviews to Rails with the bw_session cookie's
 * JWT. Backs the account page's "My reviews" list (the caller's own
 * reviews, including hidden ones). `no-store` — a stale list would show
 * a review the user just deleted, or miss one they just wrote.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../../lib/api-proxy';

export async function GET(request: NextRequest) {
  return proxyAuthed(`/api/v1/profile/reviews${request.nextUrl.search ?? ''}`, {
    cache: 'no-store',
  });
}
