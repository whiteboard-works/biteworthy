'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import {
  fetchHistory,
  HistoryError,
  type HistoryVisit,
} from '../../lib/history';

/**
 * Phase 4.8 — "My filtered menus" history.
 *
 * Authenticated. Renders the user's recent restaurant visits with
 * the visible/hidden item counts AT VIEW TIME, so the user can see
 * exactly what the filter was hiding when they last looked.
 *
 * 401 → bounce to /login. The proxy reads the bw_session cookie
 * server-side; the client just hits /api/profile/history with
 * credentials.
 */
export default function HistoryPage() {
  const router = useRouter();

  const [visits, setVisits] = useState<HistoryVisit[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchHistory()
      .then((res) => {
        if (cancelled) return;
        setVisits(res.visits);
        setTotal(res.total);
      })
      .catch((e) => {
        if (cancelled) return;
        if (e instanceof HistoryError && e.status === 401) {
          router.replace('/login?next=%2Fhistory');
          return;
        }
        setError((e as Error).message);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [router]);

  return (
    <main className="mx-auto max-w-3xl px-bw-6 py-bw-12">
      <p className="text-bite text-bw-sm font-semibold uppercase tracking-wider">My history</p>
      <h1 className="mt-bw-2 text-bw-3xl font-bold">Recent menus you've filtered</h1>
      <p className="mt-bw-2 text-bw-base text-zinc-700">
        {total === 0 && !loading
          ? "You haven't browsed any restaurants yet."
          : `${total} visit${total === 1 ? '' : 's'} on record.`}
      </p>

      {loading && <p className="mt-bw-6 text-bw-sm text-zinc-500">Loading…</p>}
      {error && (
        <p className="mt-bw-6 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          {error}
        </p>
      )}

      <ul className="mt-bw-6 divide-y divide-zinc-100">
        {visits.map((v) => (
          <VisitRow key={v.id} visit={v} />
        ))}
      </ul>
    </main>
  );
}

function VisitRow({ visit }: { visit: HistoryVisit }) {
  const when = new Date(visit.viewed_on).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
  return (
    <li className="py-bw-3" data-testid={`visit-${visit.id}`}>
      <Link
        href={`/restaurants/${encodeURIComponent(visit.restaurant.slug)}`}
        className="font-bold text-zinc-900 hover:text-bite-dark"
      >
        {visit.restaurant.name}
      </Link>
      <p className="mt-1 text-bw-sm text-zinc-500">
        {when} · {visit.restaurant.city.name}, {visit.restaurant.city.region}
      </p>
      <p className="mt-1 text-bw-sm text-zinc-700">
        Saw <span className="font-bold">{visit.items_visible_count}</span> item
        {visit.items_visible_count === 1 ? '' : 's'}
        {visit.items_hidden_count > 0
          ? `, hiding ${visit.items_hidden_count}.`
          : '.'}
      </p>
    </li>
  );
}
