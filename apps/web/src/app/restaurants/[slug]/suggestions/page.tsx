'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import {
  decideSuggestion,
  fetchSuggestionsForRestaurant,
  SuggestionError,
  type SuggestionPayload,
} from '../../../../lib/suggestions';

/**
 * Phase 4.10 — owner queue for community-edit suggestions.
 *
 * Authenticated and gated to the restaurant's
 * `claimed_by_user_id` (or admin) by the API. 401 → /login,
 * 403 → "you don't own this restaurant."
 */
export default function SuggestionQueuePage() {
  const params = useParams<{ slug: string }>();
  const slug = params.slug;
  const router = useRouter();

  const [suggestions, setSuggestions] = useState<SuggestionPayload[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<{ status: number; message: string } | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchSuggestionsForRestaurant(slug)
      .then((res) => {
        if (!cancelled) setSuggestions(res.suggestions);
      })
      .catch((e) => {
        if (cancelled) return;
        if (e instanceof SuggestionError && e.status === 401) {
          router.replace(`/login?next=${encodeURIComponent(`/restaurants/${slug}/suggestions`)}`);
          return;
        }
        if (e instanceof SuggestionError) setError({ status: e.status, message: e.message });
        else setError({ status: 500, message: (e as Error).message });
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [slug, router]);

  const decide = async (id: string, decision: 'accepted' | 'rejected') => {
    setBusyId(id);
    try {
      await decideSuggestion(id, decision);
      // Drop the row from the queue locally (it's no longer pending).
      setSuggestions((prev) => prev.filter((s) => s.id !== id));
    } catch (e) {
      const message = (e as Error).message;
      window.alert(message); // simple feedback for owner — pending UX upgrade
    } finally {
      setBusyId(null);
    }
  };

  return (
    <main className="mx-auto max-w-3xl px-bw-6 py-bw-12">
      <p className="text-bite text-bw-sm font-semibold uppercase tracking-wider">
        <Link href={`/restaurants/${slug}`} className="hover:underline">← Back to restaurant</Link>
      </p>
      <h1 className="mt-bw-2 text-bw-2xl font-bold">Community suggestions</h1>
      <p className="mt-bw-2 text-bw-sm text-zinc-500">
        Pending fixes diners have submitted for items at this restaurant.
      </p>

      {loading && <p className="mt-bw-6 text-bw-sm text-zinc-500">Loading…</p>}

      {error?.status === 403 && (
        <p className="mt-bw-6 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          You don&rsquo;t own this restaurant. Only the verified owner can review suggestions.
        </p>
      )}
      {error && error.status !== 403 && (
        <p className="mt-bw-6 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          {error.message}
        </p>
      )}

      {!loading && !error && suggestions.length === 0 && (
        <p className="mt-bw-6 text-bw-base text-zinc-500">No pending suggestions. Inbox zero.</p>
      )}

      <ul className="mt-bw-4 divide-y divide-zinc-100">
        {suggestions.map((s) => (
          <SuggestionRow key={s.id} suggestion={s} busy={busyId === s.id} onDecide={decide} />
        ))}
      </ul>
    </main>
  );
}

function SuggestionRow({
  suggestion,
  busy,
  onDecide,
}: {
  suggestion: SuggestionPayload;
  busy: boolean;
  onDecide: (id: string, decision: 'accepted' | 'rejected') => void;
}) {
  return (
    <li className="py-bw-4" data-testid={`suggestion-${suggestion.id}`}>
      <p className="text-bw-sm font-semibold text-zinc-700">
        {suggestion.kind} on{' '}
        <span className="text-zinc-900">{suggestion.item?.name ?? 'unknown item'}</span>
      </p>
      <pre className="mt-1 overflow-x-auto rounded-bw-md bg-zinc-50 p-bw-2 text-bw-xs text-zinc-700">
        {JSON.stringify(suggestion.payload, null, 2)}
      </pre>
      <p className="mt-1 text-bw-xs text-zinc-500">
        from {suggestion.submitter?.handle ? `@${suggestion.submitter.handle}` : 'anonymous diner'} ·{' '}
        {new Date(suggestion.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
      </p>
      <div className="mt-bw-2 flex gap-bw-2">
        <button
          type="button"
          disabled={busy}
          onClick={() => onDecide(suggestion.id, 'accepted')}
          data-testid={`accept-${suggestion.id}`}
          className={[
            'rounded-bw-md bg-ok px-bw-3 py-bw-2 text-bw-sm font-bold text-white',
            busy ? 'opacity-60' : 'hover:opacity-90',
          ].join(' ')}
        >
          Accept
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() => onDecide(suggestion.id, 'rejected')}
          data-testid={`reject-${suggestion.id}`}
          className={[
            'rounded-bw-md border border-zinc-300 bg-white px-bw-3 py-bw-2 text-bw-sm font-semibold text-zinc-700',
            busy ? 'opacity-60' : 'hover:border-zinc-400',
          ].join(' ')}
        >
          Reject
        </button>
      </div>
    </li>
  );
}
