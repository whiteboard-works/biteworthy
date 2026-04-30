'use client';

import { useState, type FormEvent } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { login, AuthError } from '../../lib/auth';

/**
 * Phase 4.1 — web login page.
 *
 * Posts to the Next API route at `/api/auth/login` which proxies to
 * Rails and sets the HttpOnly `bw_session` cookie. After success the
 * user is bounced to `?next=…` (or the home page) — no JWT-paste,
 * no token in the URL.
 */
export default function LoginPage() {
  const router = useRouter();
  const params = useSearchParams();
  const next = params.get('next') ?? '/';

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
    try {
      setSubmitting(true);
      await login(email, password);
      router.replace(next);
    } catch (err) {
      const status = err instanceof AuthError ? err.status : 0;
      setError(status === 401 ? 'Wrong email or password.' : (err as Error).message);
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

      <p className="mt-bw-6 text-bw-sm text-zinc-500">
        Don&rsquo;t have an account?{' '}
        <Link href={`/signup${next !== '/' ? `?next=${encodeURIComponent(next)}` : ''}`} className="font-semibold text-bite hover:text-bite-dark">
          Create one
        </Link>
      </p>
    </main>
  );
}
