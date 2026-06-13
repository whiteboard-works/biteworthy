/**
 * Phase 5.10 — Next proxy for the waitlist signup endpoint.
 *
 * `POST /api/waitlist` from the marketing landing form forwards
 * to the Rails `POST /api/v1/waitlist_signups` with the same body.
 * Keeps `NEXT_PUBLIC_API_BASE` server-side so the browser sees only
 * a same-origin request (no CORS preflight needed for this form).
 */

import { NextResponse, type NextRequest } from 'next/server';

import { API_BASE } from '../../../lib/api-base';

interface SignupBody {
  email?: string;
  source?: string;
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  const body = (await request.json().catch(() => ({}))) as SignupBody;

  const upstream = await fetch(`${API_BASE}/api/v1/waitlist_signups`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({
      waitlist_signup: {
        email: body.email ?? '',
        source: body.source ?? 'landing',
      },
    }),
  });

  const responseBody = await upstream.json().catch(() => ({}));
  return NextResponse.json(responseBody, { status: upstream.status });
}
