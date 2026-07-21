'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { logout } from '../lib/auth';

/**
 * Site-wide top bar. Until now the app had no nav at all: there was no
 * way to reach /login, and a signed-in user got no indication they were
 * logged in (the HttpOnly `bw_session` cookie is invisible to JS).
 *
 * Auth state comes from `GET /api/auth/session` (a `{ signedIn,
 * onboarded }` read the server does against the cookie) rather than a
 * cookie the client reads directly — so the SSR/SEO pages stay static
 * and only this component pays the per-request read.
 *
 * `onboarded` drives the resume nudge: a user who signed up but skipped
 * the dietary-profile setup gets a quiet "Food profile" nav link plus a
 * dismissible banner, both of which vanish once onboarding is done.
 */

// Persisted so a dismissed nudge doesn't reappear on every navigation.
// The banner still stops for good once `onboarded` flips true regardless.
const NUDGE_DISMISSED_KEY = 'bw_profile_nudge_dismissed';

// The nudge is noise on the auth + onboarding pages themselves.
function nudgeSuppressed(pathname: string): boolean {
  return (
    pathname.startsWith('/onboarding') ||
    pathname.startsWith('/login') ||
    pathname.startsWith('/signup')
  );
}

export function SiteHeader() {
  const router = useRouter();
  const pathname = usePathname();
  // null = not yet known; render a neutral bar to avoid a Sign-in →
  // Account flash and the layout shift that comes with it.
  const [signedIn, setSignedIn] = useState<boolean | null>(null);
  // Default true so the nudge never flashes before the session resolves.
  const [onboarded, setOnboarded] = useState(true);
  const [loggingOut, setLoggingOut] = useState(false);
  const [nudgeDismissed, setNudgeDismissed] = useState(false);

  useEffect(() => {
    try {
      setNudgeDismissed(localStorage.getItem(NUDGE_DISMISSED_KEY) === '1');
    } catch {
      // localStorage unavailable (private mode) — treat as not dismissed.
    }
  }, []);

  // Re-read on every navigation (keyed on pathname), not just mount: a
  // login/logout redirect is a soft nav that keeps this component
  // mounted, so a mount-only check would show stale "Sign in" right
  // after signing in. Keying on pathname also refreshes `onboarded`
  // after the onboarding flow redirects home. The previous value stays
  // put while re-fetching, so there's no flash between routes.
  useEffect(() => {
    let active = true;
    fetch('/api/auth/session', { credentials: 'same-origin' })
      .then((r) => (r.ok ? r.json() : { signedIn: false, onboarded: true }))
      .then((d: { signedIn?: boolean; onboarded?: boolean }) => {
        if (!active) return;
        setSignedIn(Boolean(d.signedIn));
        setOnboarded(d.onboarded !== false);
      })
      .catch(() => {
        if (active) setSignedIn(false);
      });
    return () => {
      active = false;
    };
  }, [pathname]);

  const onLogout = async () => {
    setLoggingOut(true);
    try {
      await logout();
    } catch {
      // The cookie is cleared client-side regardless; a failed upstream
      // jti-rotation still leaves the browser signed out.
    }
    setSignedIn(false);
    setLoggingOut(false);
    router.replace('/');
    router.refresh();
  };

  const dismissNudge = () => {
    setNudgeDismissed(true);
    try {
      localStorage.setItem(NUDGE_DISMISSED_KEY, '1');
    } catch {
      // Best-effort — a non-persisted dismiss just reappears next load.
    }
  };

  const needsProfile = signedIn === true && !onboarded;
  const showNudge = needsProfile && !nudgeDismissed && !nudgeSuppressed(pathname);

  return (
    <>
      <header
        data-testid="site-header"
        className="flex items-center justify-between border-b border-zinc-200 bg-white px-bw-6 py-bw-3"
      >
        <Link href="/" className="text-bw-lg font-bold text-bite hover:text-bite-dark">
          BiteWorthy
        </Link>

        {/* Reserve height while auth state resolves so the bar doesn't jump. */}
        <nav className="flex min-h-[1.5rem] items-center gap-bw-4 text-bw-sm">
          {signedIn === true && (
            <>
              {needsProfile && (
                <Link
                  href="/onboarding"
                  data-testid="nav-food-profile"
                  className="font-semibold text-bite hover:text-bite-dark"
                >
                  Food profile
                </Link>
              )}
              <Link
                href="/profile/settings"
                data-testid="nav-account"
                className="font-semibold text-zinc-700 hover:text-bite-dark"
              >
                Account
              </Link>
              <button
                type="button"
                onClick={onLogout}
                disabled={loggingOut}
                data-testid="nav-logout"
                className="font-semibold text-zinc-500 hover:text-zinc-800 disabled:opacity-60"
              >
                {loggingOut ? 'Logging out…' : 'Log out'}
              </button>
            </>
          )}
          {signedIn === false && (
            <>
              <Link
                href="/login"
                data-testid="nav-signin"
                className="font-semibold text-zinc-700 hover:text-bite-dark"
              >
                Sign in
              </Link>
              <Link
                href="/signup"
                data-testid="nav-signup"
                className="rounded-bw-md bg-bite px-bw-3 py-bw-1 font-bold text-white hover:bg-bite-dark"
              >
                Sign up
              </Link>
            </>
          )}
        </nav>
      </header>

      {showNudge && (
        <div
          role="note"
          data-testid="profile-nudge"
          className="flex items-center justify-between gap-bw-3 border-b border-warn/40 bg-warn/10 px-bw-6 py-bw-2 text-bw-sm text-zinc-800"
        >
          <span>
            Your food filter isn&rsquo;t set up yet —{' '}
            <Link
              href="/onboarding"
              data-testid="profile-nudge-cta"
              className="font-bold text-bite hover:text-bite-dark"
            >
              set it up →
            </Link>
          </span>
          <button
            type="button"
            onClick={dismissNudge}
            data-testid="profile-nudge-dismiss"
            className="shrink-0 font-semibold text-zinc-500 hover:text-zinc-800"
          >
            Dismiss
          </button>
        </div>
      )}
    </>
  );
}
