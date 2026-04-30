'use client';

import { useState, type FormEvent } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { signup, AuthError } from '../../lib/auth';

/**
 * Phase 4.1 — web signup page. Posts to `/api/auth/signup` (Next
 * proxy → Rails) and gets the user signed in via the same HttpOnly
 * cookie path as login.
 */
export default function SignupPage() {
  const router = useRouter();
  const params = useSearchParams();
  const next = params.get('next') ?? '/onboarding';

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
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
    try {
      setSubmitting(true);
      await signup(email, password);
      router.replace(next);
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

        {error && (
          <p className="rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
            {error}
          </p>
        )}

        <button
          type="submit"
          disabled={submitting}
          data-testid="signup-submit"
          className={[
            'mt-bw-2 rounded-bw-md bg-bite px-bw-4 py-bw-3 font-bold text-white',
            submitting ? 'opacity-60' : 'hover:bg-bite-dark',
          ].join(' ')}
        >
          {submitting ? 'Creating…' : 'Create account'}
        </button>
      </form>

      <p className="mt-bw-6 text-bw-sm text-zinc-500">
        Already have an account?{' '}
        <Link href={`/login${next !== '/onboarding' ? `?next=${encodeURIComponent(next)}` : ''}`} className="font-semibold text-bite hover:text-bite-dark">
          Sign in
        </Link>
      </p>
    </main>
  );
}
