/**
 * Phase 5.10 — soft-launch waitlist client.
 *
 * Browser-side calls hit the Next proxy at `/api/waitlist`, which
 * forwards to the Rails endpoint with `Content-Type: application/json`.
 * Direct API access (e.g. mobile, server-side) can call
 * `submitWaitlistViaApi` against the API base.
 */

const EMAIL_REGEX = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export type WaitlistSource = 'landing' | 'press' | 'footer' | 'mobile_app';

export class WaitlistError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
    this.name = 'WaitlistError';
  }
}

export interface WaitlistResult {
  ok: true;
  duplicate: boolean;
}

/**
 * Lenient email check — catches the obvious typos (no `@`, no `.`,
 * whitespace) but doesn't try to enforce RFC 5322. Server-side
 * validation is the real filter; this just keeps form submits
 * snappy by failing trivially-bad input without a roundtrip.
 */
export function isValidEmail(email: string): boolean {
  return EMAIL_REGEX.test(email.trim());
}

export interface SubmitOptions {
  fetchImpl?: typeof fetch;
}

/**
 * Browser-friendly path: posts to the Next proxy at /api/waitlist,
 * which tucks NEXT_PUBLIC_API_BASE in server-side.
 */
export async function submitWaitlist(
  email: string,
  source: WaitlistSource = 'landing',
  opts: SubmitOptions = {},
): Promise<WaitlistResult> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl('/api/waitlist', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({ email, source }),
  });
  if (!res.ok) {
    throw new WaitlistError(res.status, `submitWaitlist failed: ${res.status}`);
  }
  return (await res.json()) as WaitlistResult;
}
