/**
 * `GET /api/admin/dashboard` → Rails `GET /api/v1/admin/dashboard`.
 * adminProxy relays the Rails status verbatim (401 signed out, 404
 * non-admin) and stamps Cache-Control: no-store.
 */
import { adminProxy } from '../../../../lib/api-proxy';

export async function GET() {
  return adminProxy('/api/v1/admin/dashboard');
}
