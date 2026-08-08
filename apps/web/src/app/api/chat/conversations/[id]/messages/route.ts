/**
 * Runs one chat turn, relaying the API's Server-Sent Events straight
 * through. A turn is several model calls plus the tools between them, so
 * this handler stays open for as long as that takes.
 */
import { type NextRequest } from 'next/server';
import { proxyStream } from '../../../../../../lib/api-proxy';

// A turn with a menu scan in it legitimately runs past a minute. The
// platform clamps this to whatever the plan allows; asking for less would
// cut a working turn short.
export const maxDuration = 300;
export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return proxyStream(`/api/v1/conversations/${encodeURIComponent(id)}/messages`, await request.text());
}
