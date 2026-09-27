/**
 * Headers that let Rails throttle a server-side call by the visitor who
 * caused it rather than by this Next server — without them every
 * anonymous web visitor shares one Rack::Attack bucket.
 *
 * Rails believes `X-BW-Client-IP` only alongside a matching
 * `X-BW-Proxy-Secret` (`WEB_PROXY_SECRET`, server-only, never
 * `NEXT_PUBLIC_`). With the secret unset, or outside a request (build,
 * ISR revalidation), this returns nothing and Rails falls back to the
 * connection IP. Signed-in calls don't need it: they're throttled per user.
 *
 * Server-only: `next/headers` must never reach a client bundle.
 */
import { headers } from 'next/headers';

export async function edgeHeaders(): Promise<Record<string, string>> {
  const secret = process.env.WEB_PROXY_SECRET;
  if (!secret) return {};
  try {
    const h = await headers();
    const ip = h.get('x-forwarded-for')?.split(',')[0]?.trim() || h.get('x-real-ip')?.trim();
    if (!ip) return {};
    return { 'X-BW-Client-IP': ip, 'X-BW-Proxy-Secret': secret };
  } catch {
    return {};
  }
}
