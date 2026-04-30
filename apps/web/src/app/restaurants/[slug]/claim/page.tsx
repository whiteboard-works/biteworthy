'use client';

import { useEffect, useState } from 'react';
import { useParams, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import {
  ClaimError,
  verifyClaim,
  type VerifyResult,
} from '../../../../lib/restaurant-claim';

/**
 * Phase 4.9 — verify landing page.
 *
 * The mailer's link points here: `/restaurants/<slug>/claim?t=<token>`.
 * Anonymous — the token IS the credential. Renders a success or
 * an error state; success links back to the restaurant page.
 */
export default function ClaimVerifyPage() {
  const params = useParams<{ slug: string }>();
  const search = useSearchParams();
  const slug = params.slug;
  const token = search.get('t') ?? '';

  const [result, setResult] = useState<VerifyResult | null>(null);
  const [error, setError] = useState<{ status: number; kind?: string } | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!slug || !token) {
      setError({ status: 400 });
      setLoading(false);
      return;
    }
    let cancelled = false;
    verifyClaim(slug, token)
      .then((r) => {
        if (!cancelled) setResult(r);
      })
      .catch((e) => {
        if (cancelled) return;
        if (e instanceof ClaimError) setError({ status: e.status, kind: e.kind });
        else setError({ status: 500 });
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [slug, token]);

  return (
    <main className="mx-auto max-w-xl px-bw-6 py-bw-12">
      <p className="text-bite text-bw-sm font-semibold uppercase tracking-wider">Restaurant claim</p>
      <h1 className="mt-bw-2 text-bw-2xl font-bold">Verifying your link…</h1>

      {loading && <p className="mt-bw-3 text-bw-sm text-zinc-500">One moment.</p>}

      {result && (
        <div className="mt-bw-4 rounded-bw-md border border-zinc-200 p-bw-4">
          <p className="text-bw-base text-zinc-900">
            ✅ You now own <strong>{result.restaurant.name}</strong> on BiteWorthy.
          </p>
          <Link
            href={`/restaurants/${encodeURIComponent(result.restaurant.slug)}`}
            data-testid="back-to-restaurant"
            className="mt-bw-3 inline-block rounded-bw-md bg-bite px-bw-3 py-bw-2 text-bw-sm font-bold text-white hover:bg-bite-dark"
          >
            Open your restaurant page →
          </Link>
        </div>
      )}

      {error && !result && (
        <div className="mt-bw-4 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-base text-bite-dark">
          {explainError(error.status, error.kind)}
        </div>
      )}
    </main>
  );
}

function explainError(status: number, kind?: string): string {
  if (kind === 'ExpiredTokenError') return 'This verification link has expired. Request a fresh one from the restaurant page.';
  if (kind === 'AlreadyClaimedError') return 'This restaurant has already been claimed.';
  if (kind === 'InvalidTokenError') return 'This link is invalid. Double-check the URL or request a fresh one.';
  if (status === 400) return 'Missing slug or token in the URL.';
  return `Could not verify (${status}). Try again or contact support.`;
}
