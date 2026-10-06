import { type NextRequest } from 'next/server';
import { proxyAuthed } from '../../../lib/api-proxy';

export async function GET(request: NextRequest) {
  return proxyAuthed(`/api/v1/photo_submissions${request.nextUrl.search ?? ''}`);
}
