'use client';

import { Suspense, useState, type FormEvent } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import type { Route } from 'next';
import { login, AuthError, authFailureReason } from '../../lib/auth';
import { safeNext } from '../../lib/safe-next';
import { useTracker } from '../_PostHogProvider';

/**
 * Phase 4.1 — web login page.
 *
 * Posts to the Next API route at `/api/auth/login` which proxies to
 * Rails and sets the HttpOnly `bw_session` cookie. After success the
 * user is bounced to `?next=…` (or the home page) — no JWT-paste,
 * no token in the URL.
 *
 * Instrumented with the auth funnel events (auth_started → auth_completed
 * / auth_failed) so we can see conversion + where sign-in breaks. Only a
 * coarse failure reason is sent — never the email or password.
 */
export default function LoginPage() {
  // useSearchParams (in LoginForm) needs a Suspense boundary or the
  // production build fails prerendering — same pattern as /onboarding.
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}

function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const tracker = useTracker();
  // Sanitised here rather than at the redirect, so the value that reaches
  // the cross-link to /signup is the safe one too — otherwise a hostile
  // `next` just rides one hop further before it is used.
  const next = safeNext(params.get('next'), '/');
  // Set by /reset-password on success — confirm before they retype.
  const justReset = params.get('reset') === '1';

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    tracker.track('auth_started', { method: 'login' });
    if (!email || !password) {
      setError('Email and password required.');
      tracker.track('auth_failed', { method: 'login', reason: 'missing_fields' });
      return;
    }
    try {
      setSubmitting(true);
      await login(email, password);
      tracker.track('auth_completed', { method: 'login' });
      // `next` is a runtime query value — typedRoutes can't prove it.
      router.replace(next as Route);
    } catch (err) {
      const status = err instanceof AuthError ? err.status : 0;
      setError(status === 401 ? 'Wrong email or password.' : (err as Error).message);
      tracker.track('auth_failed', {
        method: 'login',
        reason: authFailureReason(status, { 401: 'wrong_credentials' }),
        // Only attach a real HTTP status; 0 means it never reached the API.
        ...(status > 0 ? { status } : {}),
      });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <main className="mx-auto max-w-sm px-bw-6 py-bw-12">
      <h1 className="text-bw-2xl font-bold">Sign in</h1>
      <p className="mt-bw-2 text-bw-sm text-zinc-500">
        Use your BiteWorthy email + password.
      </p>

      {justReset && (
        <p
          className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark"
          data-testid="password-reset-done"
        >
          Password updated — sign in with your new password.
        </p>
      )}

      <form onSubmit={onSubmit} className="mt-bw-6 flex flex-col gap-bw-3">
        <label className="flex flex-col gap-1">
          <span className="text-bw-sm font-semibold text-zinc-700">Email</span>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="email"
            required
            aria-label="email"
            className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base"
          />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-bw-sm font-semibold text-zinc-700">Password</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
            required
            aria-label="password"
            className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base"
          />
        </label>

        {error && (
          <p className="rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
            {error}
          </p>
        )}

        <button
          type="submit"
          disabled={submitting}
          data-testid="login-submit"
          className={[
            'mt-bw-2 rounded-bw-md bg-bite px-bw-4 py-bw-3 font-bold text-white',
            submitting ? 'opacity-60' : 'hover:bg-bite-dark',
          ].join(' ')}
        >
          {submitting ? 'Signing in…' : 'Sign in'}
        </button>
      </form>

      <p className="mt-bw-3 text-bw-sm text-zinc-500">
        <Link
          href="/forgot-password"
          data-testid="forgot-password-link"
          className="font-semibold text-bite hover:text-bite-dark"
        >
          Forgot your password?
        </Link>
      </p>

      <p className="mt-bw-6 text-bw-sm text-zinc-500">
        Don&rsquo;t have an account?{' '}
        <Link href={`/signup${next !== '/' ? `?next=${encodeURIComponent(next)}` : ''}` as Route} className="font-semibold text-bite hover:text-bite-dark">
          Create one
        </Link>
      </p>
    </main>
  );
}
