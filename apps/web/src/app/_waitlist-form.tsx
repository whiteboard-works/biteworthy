'use client';

import { useState, type FormEvent, type ReactElement } from 'react';
import { isValidEmail, submitWaitlist, WaitlistError } from '../lib/waitlist';

/**
 * Phase 5.10 — soft-launch waitlist form on the marketing landing.
 *
 * Client island so the form can submit without a full page reload.
 * Lives in `apps/web/src/app/_waitlist-form.tsx` (underscore prefix
 * keeps Next from registering it as a route).
 *
 * Disables itself + shows a thank-you when submitWaitlist resolves.
 * Inline error message on a 422 (e.g. malformed email the
 * client-side regex didn't catch).
 */
export default function WaitlistForm(): ReactElement {
  const [email, setEmail] = useState('');
  const [state, setState] = useState<'idle' | 'sending' | 'done' | 'error'>('idle');
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);

    const trimmed = email.trim();
    if (!isValidEmail(trimmed)) {
      setError('That email looks off — typo?');
      return;
    }

    try {
      setState('sending');
      await submitWaitlist(trimmed, 'landing');
      setState('done');
    } catch (e) {
      setState('error');
      setError(
        e instanceof WaitlistError
          ? `Couldn't sign you up (${e.status}). Try again in a sec?`
          : 'Network hiccup — try again?',
      );
    }
  };

  if (state === 'done') {
    return (
      <p
        data-testid="waitlist-thanks"
        className="mt-bw-2 inline-block rounded-bw-md bg-bite-light px-bw-4 py-bw-3 text-bw-base font-semibold text-bite-dark"
      >
        ✓ You&rsquo;re on the list. We&rsquo;ll send one email 48 hours before public release.
      </p>
    );
  }

  return (
    <form onSubmit={submit} data-testid="waitlist-form" className="mt-bw-2 flex flex-wrap items-center gap-bw-3">
      <input
        type="email"
        required
        inputMode="email"
        placeholder="you@example.com"
        aria-label="Email address"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        disabled={state === 'sending'}
        className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base text-zinc-900 placeholder:text-zinc-400 focus:border-bite focus:outline-none disabled:opacity-60"
      />
      <button
        type="submit"
        disabled={state === 'sending'}
        data-testid="waitlist-submit"
        className="rounded-bw-md bg-bite px-bw-4 py-bw-2 text-bw-base font-bold text-white hover:bg-bite-dark disabled:opacity-60"
      >
        {state === 'sending' ? 'Adding…' : 'Get early access'}
      </button>
      {error && (
        <p className="basis-full text-bw-sm text-bite-dark" data-testid="waitlist-error">
          {error}
        </p>
      )}
    </form>
  );
}
