/**
 * Answers a parked destructive tool call. Same streaming relay as a
 * message: approving one resumes the turn, which can run further tools
 * and park again.
 */
import { type NextRequest } from 'next/server';
import { proxyStream } from '../../../../../../lib/api-proxy';

export const maxDuration = 300;
export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return proxyStream(`/api/v1/conversations/${encodeURIComponent(id)}/confirm`, await request.text());
}
