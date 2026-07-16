'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { logout } from '../lib/auth';

/**
 * Site-wide top bar. Until now the app had no nav at all: there was no
 * way to reach /login, and a signed-in user got no indication they were
 * logged in (the HttpOnly `bw_session` cookie is invisible to JS).
 *
 * Auth state comes from `GET /api/auth/session` (a `{ signedIn }` read
 * that the server does against the cookie) rather than a cookie the
 * client reads directly — so the SSR/SEO pages stay static and only
 * this component pays the per-request read.
 */
export function SiteHeader() {
  const router = useRouter();
  // null = not yet known; render a neutral bar to avoid a Sign-in →
  // Account flash and the layout shift that comes with it.
  const [signedIn, setSignedIn] = useState<boolean | null>(null);
  const [loggingOut, setLoggingOut] = useState(false);

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
  }, []);

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

  return (
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
          <Link
            href="/login"
            data-testid="nav-signin"
            className="font-semibold text-bite hover:text-bite-dark"
          >
            Sign in
          </Link>
        )}
      </nav>
    </header>
  );
}
