'use client';

import { Suspense, useState, type FormEvent } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { AuthError, resetPassword } from '../../lib/auth';

/**
 * Landing page for the emailed reset link
 * (`/reset-password?reset_password_token=…`). Consumes the token via
 * the auth proxy and sends the user to /login on success.
 */
export default function ResetPasswordPage() {
  // useSearchParams needs a Suspense boundary or the prod build bails
  // the page out of static rendering — same pattern as /login.
  return (
    <Suspense>
      <ResetPasswordForm />
    </Suspense>
  );
}

function ResetPasswordForm() {
  const router = useRouter();
  const params = useSearchParams();
  const token = params.get('reset_password_token') ?? '';

  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!token) {
    return (
      <main className="mx-auto max-w-sm px-bw-6 py-bw-12">
        <h1 className="text-bw-2xl font-bold">Reset link missing</h1>
        <p className="mt-bw-3 text-bw-base text-zinc-700" data-testid="reset-no-token">
          This page only works from the link in a reset email.
        </p>
        <p className="mt-bw-6 text-bw-sm text-zinc-500">
          <Link href="/forgot-password" className="font-semibold text-bite hover:text-bite-dark">
            Request a new reset link →
          </Link>
        </p>
      </main>
    );
  }

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (password.length < 8) {
      setError('Password must be at least 8 characters.');
      return;
    }
    if (password !== confirmation) {
      setError('Passwords do not match.');
      return;
    }
    try {
      setSubmitting(true);
      await resetPassword(token, password, confirmation);
      router.replace('/login?reset=1');
    } catch (err) {
      // 422 = Devise refused the token (expired/used) or the password.
      // The proxy flattens Devise's errors into the message.
      const status = err instanceof AuthError ? err.status : 0;
      setError(
        status === 422
          ? `${(err as Error).message}. If the link is old, request a new one below.`
          : (err as Error).message,
      );
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <main className="mx-auto max-w-sm px-bw-6 py-bw-12">
      <h1 className="text-bw-2xl font-bold">Choose a new password</h1>

      <form onSubmit={onSubmit} className="mt-bw-6 flex flex-col gap-bw-3">
        <label className="flex flex-col gap-1">
          <span className="text-bw-sm font-semibold text-zinc-700">New password</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="new-password"
            required
            minLength={8}
            aria-label="new-password"
            className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base"
          />
        </label>
        <label className="flex flex-col gap-1">
          <span className="text-bw-sm font-semibold text-zinc-700">Confirm password</span>
          <input
            type="password"
            value={confirmation}
            onChange={(e) => setConfirmation(e.target.value)}
            autoComplete="new-password"
            required
            aria-label="confirm-password"
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
          data-testid="reset-submit"
          className={[
            'mt-bw-2 rounded-bw-md bg-bite px-bw-4 py-bw-3 font-bold text-white',
            submitting ? 'opacity-60' : 'hover:bg-bite-dark',
          ].join(' ')}
        >
          {submitting ? 'Saving…' : 'Set new password'}
        </button>
      </form>

      <p className="mt-bw-6 text-bw-sm text-zinc-500">
        Link expired?{' '}
        <Link href="/forgot-password" className="font-semibold text-bite hover:text-bite-dark">
          Request a new one
        </Link>
      </p>
    </main>
  );
}
