'use client';

import { useState, type FormEvent } from 'react';
import Link from 'next/link';
import { requestPasswordReset } from '../../lib/auth';

/**
 * Request a password-reset email. The confirmation copy is identical
 * whether or not the address has an account — the API answers 202
 * either way, and this page must not narrow that.
 */
export default function ForgotPasswordPage() {
  const [email, setEmail] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!email) {
      setError('Enter your email.');
      return;
    }
    try {
      setSubmitting(true);
      await requestPasswordReset(email);
      setSent(true);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  if (sent) {
    return (
      <main className="mx-auto max-w-sm px-bw-6 py-bw-12">
        <h1 className="text-bw-2xl font-bold">Check your email</h1>
        <p className="mt-bw-3 text-bw-base text-zinc-700" data-testid="forgot-sent">
          If <span className="font-semibold">{email}</span> has a BiteWorthy account, a reset
          link is on its way. It expires in 6 hours.
        </p>
        <p className="mt-bw-6 text-bw-sm text-zinc-500">
          <Link href="/login" className="font-semibold text-bite hover:text-bite-dark">
            ← Back to sign in
          </Link>
        </p>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-sm px-bw-6 py-bw-12">
      <h1 className="text-bw-2xl font-bold">Forgot your password?</h1>
      <p className="mt-bw-2 text-bw-sm text-zinc-500">
        Enter your email and we&rsquo;ll send a reset link.
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

        {error && (
          <p className="rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
            {error}
          </p>
        )}

        <button
          type="submit"
          disabled={submitting}
          data-testid="forgot-submit"
          className={[
            'mt-bw-2 rounded-bw-md bg-bite px-bw-4 py-bw-3 font-bold text-white',
            submitting ? 'opacity-60' : 'hover:bg-bite-dark',
          ].join(' ')}
        >
          {submitting ? 'Sending…' : 'Send reset link'}
        </button>
      </form>

      <p className="mt-bw-6 text-bw-sm text-zinc-500">
        Remembered it?{' '}
        <Link href="/login" className="font-semibold text-bite hover:text-bite-dark">
          Sign in
        </Link>
      </p>
    </main>
  );
}
