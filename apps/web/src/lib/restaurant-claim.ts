/**
 * Phase 4.9 — restaurant claim flow client.
 *
 * Both functions go through the Next proxy at
 * /api/restaurants/<slug>/claim. requestClaim needs the bw_session
 * cookie (proxy injects JWT). verifyClaim is anonymous — the token
 * IS the credential.
 */

export interface ClaimRequestResult {
  status: 'verification_sent';
  email: string;
  auto_acceptable: boolean;
  expires_at: string;
}

export interface VerifiedRestaurant {
  id: string;
  slug: string;
  name: string;
  claimed_at: string;
  claimed_by_user_id: string;
}

export interface VerifyResult {
  status: 'claimed';
  restaurant: VerifiedRestaurant;
}

export class ClaimError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly kind?: string,
  ) {
    super(message);
    this.name = 'ClaimError';
  }
}

export interface ClaimOptions {
  fetchImpl?: typeof fetch;
}

export async function requestClaim(
  slug: string,
  email: string,
  opts: ClaimOptions = {},
): Promise<ClaimRequestResult> {
  const { fetchImpl = fetch } = opts;
  const res = await fetchImpl(`/api/restaurants/${encodeURIComponent(slug)}/claim`, {
    method: 'POST',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email }),
  });
  if (!res.ok) throw await claimError(res, `requestClaim ${slug}`);
  return (await res.json()) as ClaimRequestResult;
}

export async function verifyClaim(
  slug: string,
  token: string,
  opts: ClaimOptions = {},
): Promise<VerifyResult> {
  const { fetchImpl = fetch } = opts;
  const url = `/api/restaurants/${encodeURIComponent(slug)}/claim/verify?t=${encodeURIComponent(token)}`;
  const res = await fetchImpl(url);
  if (!res.ok) throw await claimError(res, `verifyClaim ${slug}`);
  return (await res.json()) as VerifyResult;
}

async function claimError(res: Response, label: string): Promise<ClaimError> {
  let body: { error?: string; kind?: string } | null = null;
  try {
    body = (await res.json()) as { error?: string; kind?: string };
  } catch {
    // ignore
  }
  return new ClaimError(
    res.status,
    `${label} failed: ${res.status}${body?.error ? ` — ${body.error}` : ''}`,
    body?.kind,
  );
}
