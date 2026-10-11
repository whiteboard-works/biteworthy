/**
 * Where BiteWorthy's PostHog data goes, and from which hosts.
 *
 * Project 652080 (ADR 0009) is the product's own project. The token below
 * is its public client token — the value PostHog designs to be shipped in
 * every browser bundle — so it lives in code rather than in a dashboard
 * variable: a variable is the thing nobody re-checks, and the one that was
 * documented pointed at a project shared with the other Whiteboard Works
 * sites. On the production hosts the token is used unconditionally. Anywhere
 * else — localhost, a preview deploy, a self-hosted clone — the environment
 * variable decides, and unset means no analytics at all.
 */
export const POSTHOG_HOST = 'https://us.i.posthog.com';
export const POSTHOG_PROJECT_ID = 652080;
export const POSTHOG_PROJECT_TOKEN = 'phc_CPvZQiDfikVk4xEG4AvDvSbshhyExH3QdfWVtX4zN999';

const PRODUCTION_HOSTNAMES = new Set(['bite-worthy.com', 'www.bite-worthy.com']);

/**
 * The key the browser SDK initializes with: the project token on
 * bite-worthy.com, otherwise `NEXT_PUBLIC_POSTHOG_KEY` (or nothing).
 */
export function browserPostHogKey(
  hostname: string,
  envKey: string | undefined = process.env.NEXT_PUBLIC_POSTHOG_KEY,
): string | undefined {
  if (PRODUCTION_HOSTNAMES.has(hostname)) return POSTHOG_PROJECT_TOKEN;
  return envKey || undefined;
}

/**
 * The key the Next server reports with: the project token on Vercel's
 * production deployment (`VERCEL_ENV`), otherwise the same env var.
 */
export function serverPostHogKey(
  env: Record<string, string | undefined> = process.env,
): string | undefined {
  if (env.VERCEL_ENV === 'production') return POSTHOG_PROJECT_TOKEN;
  return env.NEXT_PUBLIC_POSTHOG_KEY || undefined;
}
