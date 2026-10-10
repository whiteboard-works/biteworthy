/**
 * The origin of the BiteWorthy Rails API.
 *
 * Single source of truth: every Next.js route handler (the `/api/*`
 * proxy that injects the session cookie as a Bearer header) and every
 * server-side fetch helper imports this instead of re-deriving it, as do
 * the few client components that call the API directly (public taxonomy
 * on onboarding, scan uploads): `NEXT_PUBLIC_` inlines it into the
 * browser bundle at build time.
 *
 * Defaults to the local API on :3000; production sets
 * `NEXT_PUBLIC_API_BASE` to the deployed origin.
 */
export const API_BASE = process.env.NEXT_PUBLIC_API_BASE ?? 'http://localhost:3000';
