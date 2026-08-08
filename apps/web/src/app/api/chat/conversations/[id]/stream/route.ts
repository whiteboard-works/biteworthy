/**
 * Reads a turn's narration. Separate from the request that starts one,
 * because the turn runs in a job now and outlives any single connection —
 * which is what lets a reconnect resume rather than start over.
 */
import { type NextRequest } from 'next/server';
import { proxyStreamGet } from '../../../../../../lib/api-proxy';

export const maxDuration = 300;
export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  const after = request.nextUrl.searchParams.get('after') ?? '';
  return proxyStreamGet(
    `/api/v1/conversations/${encodeURIComponent(id)}/stream?after=${encodeURIComponent(after)}`,
  );
}
