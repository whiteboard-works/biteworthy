'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { logout } from '../lib/auth';
import { ONBOARDED_HINT_KEY } from '../lib/onboarding';

/**
 * Site-wide top bar. Until now the app had no nav at all: there was no
 * way to reach /login, and a signed-in user got no indication they were
 * logged in (the HttpOnly `bw_session` cookie is invisible to JS).
 *
 * Two independent reads back it:
 *   - `GET /api/auth/session` → `{ signedIn }`, a fast LOCAL cookie read
 *     that never blocks on the API — so the Sign-in ↔ Account nav always
 *     resolves quickly.
 *   - `GET /api/auth/onboarded` → `{ onboarded }`, which does hit Rails.
 *     Kept separate so a slow API only delays the (optional) resume nudge,
 *     never the auth nav. It fails safe to onboarded so we never nag.
 *
 * The resume nudge (a quiet "Food profile" link + a dismissible banner)
 * shows only for a signed-in user we've CONFIRMED hasn't onboarded, and
 * vanishes the moment they finish.
 */

// Dismissed-banner + onboarding-complete flags. Both are cleared on
// logout so nothing leaks to a different account on a shared browser.
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
  // null = unknown (nudge stays hidden); only a confirmed `false` nudges.
  const [onboarded, setOnboarded] = useState<boolean | null>(null);
  const [loggingOut, setLoggingOut] = useState(false);
  const [nudgeDismissed, setNudgeDismissed] = useState(false);
  // Once we learn a user has onboarded it can't revert without a new
  // login, so latch it and stop re-fetching /api/auth/onboarded on every
  // navigation. Reset on logout.
  const onboardedConfirmed = useRef(false);
  // Admin-ness resolves once per sign-in state change (not per
  // navigation — the common answer is `false`, and per-nav re-checks
  // would cost every signed-in user a Rails round-trip on each route).
  // A mid-session grant appears after the next full load; a mid-session
  // demotion is handled by the /admin pages themselves.
  const [admin, setAdmin] = useState(false);

  useEffect(() => {
    try {
      setNudgeDismissed(localStorage.getItem(NUDGE_DISMISSED_KEY) === '1');
    } catch {
      // localStorage unavailable (private mode) — treat as not dismissed.
    }
  }, []);

  // signed-in state — re-read on every navigation (a login/logout redirect
  // is a soft nav that keeps this mounted, so a mount-only check would show
  // stale "Sign in"). Fast + local; the previous value stays put while
  // re-fetching, so there's no flash between routes.
  useEffect(() => {
    let active = true;
    fetch('/api/auth/session', { credentials: 'same-origin' })
      .then((r) => (r.ok ? r.json() : { signedIn: false }))
      .then((d: { signedIn?: boolean }) => {
        if (active) setSignedIn(Boolean(d.signedIn));
      })
      .catch(() => {
        if (active) setSignedIn(false);
      });
    return () => {
      active = false;
    };
  }, [pathname]);

  // onboarding status — only for signed-in users, and only until we've
  // confirmed they're onboarded (then latched, so onboarded users don't
  // pay a Rails round-trip on every navigation). A just-completed save
  // leaves a one-shot sessionStorage hint so the nudge flips off on the
  // redirect home without waiting for the fetch.
  useEffect(() => {
    if (signedIn !== true || onboardedConfirmed.current) return;
    try {
      if (sessionStorage.getItem(ONBOARDED_HINT_KEY) === '1') {
        sessionStorage.removeItem(ONBOARDED_HINT_KEY);
        onboardedConfirmed.current = true;
        setOnboarded(true);
        return;
      }
    } catch {
      // sessionStorage unavailable — fall through to the fetch.
    }
    let active = true;
    fetch('/api/auth/onboarded', { credentials: 'same-origin' })
      .then((r) => (r.ok ? r.json() : { onboarded: true }))
      .then((d: { onboarded?: boolean }) => {
        if (!active) return;
        const done = d.onboarded !== false;
        if (done) onboardedConfirmed.current = true;
        setOnboarded(done);
      })
      .catch(() => {
        if (active) setOnboarded(true);
      });
    return () => {
      active = false;
    };
  }, [signedIn, pathname]);

  useEffect(() => {
    if (signedIn !== true) {
      setAdmin(false);
      return;
    }
    let active = true;
    fetch('/api/auth/admin', { credentials: 'same-origin' })
      .then((r) => (r.ok ? r.json() : { admin: false }))
      .then((d: { admin?: boolean }) => {
        if (active) setAdmin(d.admin === true);
      })
      .catch(() => {
        if (active) setAdmin(false);
      });
    return () => {
      active = false;
    };
  }, [signedIn]);

  const onLogout = async () => {
    setLoggingOut(true);
    try {
      await logout();
    } catch {
      // The cookie is cleared client-side regardless; a failed upstream
      // jti-rotation still leaves the browser signed out.
    }
    setSignedIn(false);
    // Reset the nudge lifecycle so a different account signing in on this
    // browser is evaluated from scratch — neither the "confirmed
    // onboarded" latch nor the dismissal may carry across users.
    onboardedConfirmed.current = false;
    setOnboarded(null);
    setNudgeDismissed(false);
    try {
      localStorage.removeItem(NUDGE_DISMISSED_KEY);
    } catch {
      // no-op
    }
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

  const needsProfile = signedIn === true && onboarded === false;
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
          {/* Discovery — visible to everyone, signed in or not. */}
          <Link
            href="/restaurants"
            data-testid="nav-restaurants"
            className="font-semibold text-zinc-700 hover:text-bite-dark"
          >
            Restaurants
          </Link>
          {/* Scanning a menu is a conversation now — this is where the
              old "Scan a menu" link pointed before the pivot. Visible
              signed-out too: the headline feature must be discoverable,
              and /chat bounces anonymous visitors through /login. */}
          <Link
            href="/chat"
            data-testid="nav-chat"
            className="font-semibold text-zinc-700 hover:text-bite-dark"
          >
            Chat
          </Link>
          {signedIn === true && (
            <>
              {needsProfile && (
                <Link
                  href="/onboarding"
                  data-testid="nav-food-profile"
                  className="font-semibold text-zinc-700 hover:text-bite-dark"
                >
                  Food profile
                </Link>
              )}
              {admin && (
                <Link
                  href="/admin"
                  data-testid="nav-admin"
                  className="font-semibold text-zinc-700 hover:text-bite-dark"
                >
                  Admin
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
