/**
 * The OAuth grants this person has handed out.
 *
 * Read-only here on purpose — a connection is created by walking the
 * consent flow at `/oauth/consent`, never by posting to a list.
 */
import { proxyAuthed } from '../../../lib/api-proxy';

export async function GET() {
  return proxyAuthed('/api/v1/connected_apps');
}
