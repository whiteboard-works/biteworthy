'use client';

import { useCallback, useEffect, useState, type ReactElement } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import type { Route } from 'next';

interface ConsentScope {
  name: string;
  description: string;
}

interface Consent {
  client: { name: string; uid: string; confidential: boolean };
  scopes: ConsentScope[];
  redirect_uri: string;
  state: string | null;
  user: { id: string; email: string };
}

/**
 * Approve or refuse an app's request to act on your account.
 *
 * The screen shows three things, because those are what a decision needs:
 * who is asking, where approving sends you, and what each permission
 * actually lets them do. Scope strings never appear on their own —
 * "profile:write" is not something anyone can agree to on the merits.
 *
 * The page enforces nothing. Rails validates the client, the scopes, the
 * redirect URI, and the requested audience before this ever renders, and
 * again when the browser returns.
 */
export function ConsentClient(): ReactElement {
  const router = useRouter();
  const params = useSearchParams();
  const returnTo = params.get('return_to') ?? '';

  const [consent, setConsent] = useState<Consent | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!returnTo) {
      setError('This link is missing the authorization request it was for.');
      return;
    }
    let cancelled = false;
    fetch(`/api/oauth/consent?return_to=${encodeURIComponent(returnTo)}`, { cache: 'no-store' })
      .then(async (res) => {
        if (cancelled) return;
        // Signing in has to come back *here*, or the client is left
        // waiting on an authorization that never resumes.
        if (res.status === 401) {
          const next = `/oauth/consent?return_to=${encodeURIComponent(returnTo)}`;
          router.replace(`/login?next=${encodeURIComponent(next)}` as Route);
          return;
        }
        const body = (await res.json()) as Consent & { error?: string };
        if (!res.ok) throw new Error(body.error ?? 'That authorization request is not valid.');
        setConsent(body);
      })
      .catch((e: unknown) => !cancelled && setError((e as Error).message));
    return () => {
      cancelled = true;
    };
  }, [returnTo, router]);

  const approve = useCallback(async () => {
    setSubmitting(true);
    setError(null);
    try {
      const res = await fetch('/api/oauth/consent', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ return_to: returnTo }),
      });
      const body = (await res.json()) as { redirect_to?: string; error?: string };
      if (!res.ok || !body.redirect_to) throw new Error(body.error ?? 'Could not complete that.');
      window.location.href = body.redirect_to;
    } catch (e) {
      setError((e as Error).message);
      setSubmitting(false);
    }
  }, [returnTo]);

  // A refusal goes back to the client so it can stop waiting, rather than
  // leaving it hung on a window that simply closed. The destination is
  // safe to use because the API already checked it against what the
  // client registered.
  const deny = useCallback(() => {
    if (!consent) return;
    const url = new URL(consent.redirect_uri);
    url.searchParams.set('error', 'access_denied');
    if (consent.state) url.searchParams.set('state', consent.state);
    window.location.href = url.toString();
  }, [consent]);

  if (error && !consent) {
    return (
      <main className="mx-auto max-w-lg px-bw-4 py-bw-12">
        <div
          className="rounded-bw-md border border-danger bg-danger/10 px-bw-4 py-bw-3 text-bw-base text-text"
          data-testid="consent-error"
        >
          {error}
        </div>
      </main>
    );
  }

  if (!consent) {
    return (
      <main className="mx-auto max-w-lg px-bw-4 py-bw-12">
        <p className="text-bw-base text-textMuted">Loading…</p>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-lg px-bw-4 py-bw-12" data-testid="consent">
      <h1 className="text-bw-xl font-semibold text-text">
        Connect <span className="text-bite">{consent.client.name}</span>?
      </h1>
      <p className="mt-bw-2 text-bw-sm text-textMuted">
        Signed in as {consent.user.email}. If you approve, it will be able to:
      </p>

      <ul className="mt-bw-6 flex flex-col gap-bw-3" data-testid="consent-scopes">
        {consent.scopes.map((scope) => (
          <li
            key={scope.name}
            className="rounded-bw-md border border-border bg-bgAlt px-bw-4 py-bw-3"
          >
            <p className="text-bw-base text-text">{scope.description}</p>
            <p className="mt-bw-1 font-mono text-bw-xs text-textMuted">{scope.name}</p>
          </li>
        ))}
      </ul>

      {/* An app can call itself anything. Where it sends you, it cannot
          fake — this is the URI it registered. */}
      <p className="mt-bw-6 break-all text-bw-xs text-textMuted" data-testid="consent-redirect">
        You will be returned to {consent.redirect_uri}
      </p>

      {error && (
        <p className="mt-bw-4 text-bw-sm text-danger" data-testid="consent-error">
          {error}
        </p>
      )}

      <div className="mt-bw-6 flex gap-bw-3">
        <button
          type="button"
          onClick={approve}
          disabled={submitting}
          className="rounded-bw-md bg-bite px-bw-5 py-bw-3 text-bw-base font-medium text-white disabled:opacity-50"
        >
          {submitting ? 'Connecting…' : 'Approve'}
        </button>
        <button
          type="button"
          onClick={deny}
          disabled={submitting}
          className="rounded-bw-md border border-border px-bw-5 py-bw-3 text-bw-base text-text disabled:opacity-50"
        >
          Cancel
        </button>
      </div>
    </main>
  );
}
