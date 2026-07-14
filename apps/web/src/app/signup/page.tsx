'use client';

import { Suspense, useState, type FormEvent } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import type { Route } from 'next';
import { signup, AuthError } from '../../lib/auth';

/**
 * Phase 4.1 — web signup page. Posts to `/api/auth/signup` (Next
 * proxy → Rails) and gets the user signed in via the same HttpOnly
 * cookie path as login.
 */
export default function SignupPage() {
  // useSearchParams (in SignupForm) needs a Suspense boundary or the
  // production build fails prerendering — same pattern as /onboarding.
  return (
    <Suspense>
      <SignupForm />
    </Suspense>
  );
}

function SignupForm() {
  const router = useRouter();
  const params = useSearchParams();
  const next = params.get('next') ?? '/onboarding';

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [ageConfirmed, setAgeConfirmed] = useState(false);
  const [termsAccepted, setTermsAccepted] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!email || !password) {
      setError('Email and password required.');
      return;
    }
    if (password.length < 8) {
      setError('Password must be at least 8 characters.');
      return;
    }
    if (!ageConfirmed) {
      setError('You must confirm you are at least 13 years old.');
      return;
    }
    if (!termsAccepted) {
      setError('You must agree to the Terms of Service and Privacy Policy.');
      return;
    }
    try {
      setSubmitting(true);
      await signup(email, password, ageConfirmed, termsAccepted);
      // `next` is a runtime query value — typedRoutes can't prove it.
      router.replace(next as Route);
    } catch (err) {
      const status = err instanceof AuthError ? err.status : 0;
      setError(status === 422 ? 'That email is already in use.' : (err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <main className="mx-auto max-w-sm px-bw-6 py-bw-12">
      <h1 className="text-bw-2xl font-bold">Create account</h1>
      <p className="mt-bw-2 text-bw-sm text-zinc-500">
        Free. Stores your dietary filter so it&rsquo;s ready next time.
      </p>

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
            autoComplete="new-password"
            required
            minLength={8}
            aria-label="password"
            className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base"
          />
          <span className="text-bw-xs text-zinc-500">8+ characters.</span>
        </label>

        <label className="flex items-start gap-bw-2 text-bw-sm text-zinc-700">
          <input
            type="checkbox"
            checked={ageConfirmed}
            onChange={(e) => setAgeConfirmed(e.target.checked)}
            data-testid="age-confirm"
            className="mt-bw-1 h-4 w-4 shrink-0"
          />
          <span>I am at least 13 years old.</span>
        </label>

        <label className="flex items-start gap-bw-2 text-bw-sm text-zinc-700">
          <input
            type="checkbox"
            checked={termsAccepted}
            onChange={(e) => setTermsAccepted(e.target.checked)}
            data-testid="terms-accept"
            className="mt-bw-1 h-4 w-4 shrink-0"
          />
          <span>
            I agree to the{' '}
            <Link href="/terms" className="font-semibold text-bite hover:text-bite-dark">
              Terms of Service
            </Link>{' '}
            and{' '}
            <Link href="/privacy" className="font-semibold text-bite hover:text-bite-dark">
              Privacy Policy
            </Link>
            .
          </span>
        </label>

        {error && (
          <p className="rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
            {error}
          </p>
        )}

        <button
          type="submit"
          disabled={submitting || !ageConfirmed || !termsAccepted}
          data-testid="signup-submit"
          className={[
            'mt-bw-2 rounded-bw-md bg-bite px-bw-4 py-bw-3 font-bold text-white',
            submitting || !ageConfirmed || !termsAccepted ? 'opacity-60' : 'hover:bg-bite-dark',
          ].join(' ')}
        >
          {submitting ? 'Creating…' : 'Create account'}
        </button>
      </form>

      <p className="mt-bw-6 text-bw-sm text-zinc-500">
        Already have an account?{' '}
        <Link href={`/login${next !== '/onboarding' ? `?next=${encodeURIComponent(next)}` : ''}` as Route} className="font-semibold text-bite hover:text-bite-dark">
          Sign in
        </Link>
      </p>
    </main>
  );
}
