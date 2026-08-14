/**
 * Answers a parked `ask_questions`. Same relay as a confirmation: the
 * answer resumes the turn, which can run further tools and park again.
 *
 * This existed only in `lib/chat.ts` at first, which is a shape of bug
 * the client tests cannot see — they mock the module, so a `fetch` at a
 * path with no route handler still "passes". The proxy is the thing that
 * makes the endpoint reachable at all.
 */
import { type NextRequest } from 'next/server';
import { proxyStream } from '../../../../../../lib/api-proxy';

export const maxDuration = 300;
export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  return proxyStream(`/api/v1/conversations/${encodeURIComponent(id)}/answer`, await request.text());
}
