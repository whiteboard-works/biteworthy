/**
 * Mints an upload ticket so the browser can send a scan upload straight to
 * Rails rather than through this server, whose body limit (4.5 MB on
 * Vercel) sits below the API's. The session JWT never leaves this server;
 * the ticket names the user, expires in minutes, and opens nothing but
 * POST /api/v1/attachments.
 */
import { proxyAuthed } from '../../../../../lib/api-proxy';

export function POST() {
  return proxyAuthed('/api/v1/attachments/ticket', { method: 'POST' });
}
