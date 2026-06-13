/**
 * Phase 4.8 — proxy GET /api/profile/history to Rails with the
 * bw_session cookie's JWT.
 */
import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../../lib/api-proxy';

export async function GET(request: NextRequest) {
  return proxyAuthed(`/api/v1/profile/history${request.nextUrl.search ?? ''}`);
}
