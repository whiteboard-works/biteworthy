/**
 * Proxy GET /api/profile/favorites to Rails with the bw_session
 * cookie's JWT. Backs the account page's Favorites section (the
 * caller's saved restaurants + dishes). `no-store` — a stale list
 * would show something the user just unsaved.
 */
import { proxyAuthed } from '../../../../lib/api-proxy';

export async function GET() {
  return proxyAuthed('/api/v1/profile/favorites', { cache: 'no-store' });
}
