'use client';

import { useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { ClaimError, requestClaim } from '../../../lib/restaurant-claim';
import type { Restaurant } from '../../../lib/restaurants';
import { useTracker } from '../../_PostHogProvider';

/**
 * Phase 4.9 — claim flow entry point on the restaurant page. Extracted
 * from RestaurantClient (menu-page hierarchy pass), unchanged.
 *
 * Hidden once the restaurant is already claimed. Shows a tiny inline
 * form ("@<your-domain> email"); on submit, POSTs to the claim
 * endpoint and shows a confirmation. 401 from the proxy bounces to
 * /login because the POST requires auth.
 */
export function ClaimSection({ slug, restaurant }: { slug: string; restaurant: Restaurant }) {
  const router = useRouter();
  const tracker = useTracker();
  const [email, setEmail] = useState('');
  const [open, setOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [done, setDone] = useState<{ email: string; auto: boolean } | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (restaurant.claimed_by_user_id) {
    return (
      <p className="mt-bw-3 text-bw-xs text-zinc-500" data-testid="claimed-notice">
        ✓ This restaurant is owner-claimed.
      </p>
    );
  }

  if (done) {
    return (
      <p className="mt-bw-3 text-bw-sm text-zinc-700" data-testid="claim-sent">
        Verification email sent to <strong>{done.email}</strong>. Click the link to confirm your
        claim.
        {!done.auto && (
          <span className="ml-1 text-bw-xs text-zinc-500">
            (Domain didn&rsquo;t match this restaurant&rsquo;s website — admin review may follow.)
          </span>
        )}
      </p>
    );
  }

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        data-testid="open-claim"
        className="mt-bw-3 text-bw-sm font-semibold text-bite hover:text-bite-dark"
      >
        Claim this restaurant
      </button>
    );
  }

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!email.includes('@')) {
      setError('Enter a valid email.');
      return;
    }
    try {
      setSubmitting(true);
      const result = await requestClaim(slug, email);
      setDone({ email: result.email, auto: result.auto_acceptable });
      tracker.track('restaurant_claimed', {
        restaurant_slug: slug,
        decision: result.auto_acceptable ? 'auto_acceptable' : 'admin_review',
      });
    } catch (e) {
      if (e instanceof ClaimError && e.status === 401) {
        // Keep ?profile= / ?p= across the login round-trip — a bare slug
        // would silently drop the applied filter.
        const next = `${window.location.pathname}${window.location.search}`;
        router.replace(`/login?next=${encodeURIComponent(next)}`);
        return;
      }
      setError((e as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <form
      onSubmit={submit}
      className="mt-bw-3 rounded-bw-md border border-zinc-200 p-bw-3"
      data-testid="claim-form"
    >
      <p className="text-bw-sm font-semibold text-zinc-700">Claim this restaurant</p>
      <p className="mt-1 text-bw-xs text-zinc-500">
        Use an email at the restaurant&rsquo;s own domain — we&rsquo;ll send a one-time verification
        link.
      </p>
      <input
        type="email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        placeholder="you@yourrestaurant.com"
        aria-label="claim-email"
        required
        className="mt-bw-2 w-full rounded-bw-md border border-zinc-300 px-bw-2 py-bw-2 text-bw-sm"
      />
      {error && (
        <p className="mt-bw-2 rounded-bw-md bg-bite-light px-bw-2 py-bw-1 text-bw-xs text-bite-dark">
          {error}
        </p>
      )}
      <div className="mt-bw-2 flex items-center gap-bw-2 justify-end">
        <button
          type="button"
          onClick={() => setOpen(false)}
          className="text-bw-sm font-semibold text-zinc-500 hover:text-zinc-700"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={submitting}
          data-testid="submit-claim"
          className={[
            'rounded-bw-md bg-bite px-bw-3 py-bw-2 text-bw-sm font-bold text-white',
            submitting ? 'opacity-60' : 'hover:bg-bite-dark',
          ].join(' ')}
        >
          {submitting ? 'Sending…' : 'Send verification'}
        </button>
      </div>
    </form>
  );
}
