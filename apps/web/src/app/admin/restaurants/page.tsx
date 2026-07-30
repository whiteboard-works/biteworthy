'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import {
  fetchAdminRestaurants,
  type AdminRestaurantsResponse,
} from '../../../lib/admin/management';
import { friendlyAdminError } from '../../../lib/admin/shared';
import { Pagination } from '../_Pagination';
import { StatusBadge, type BadgeTone } from '../_StatusBadge';

/**
 * /admin/restaurants — list/search across every status. The
 * "community" toggle applies the community_published lens (published
 * with community-sourced data); rows flag how many items still need
 * strict-mode graduation.
 */

const STATUSES = ['draft', 'published', 'closed'] as const;
const PAGE_SIZE = 25;

const STATUS_TONES: Record<string, BadgeTone> = {
  draft: 'muted',
  published: 'ok',
  closed: 'danger',
};

export default function AdminRestaurantsPage() {
  const [q, setQ] = useState('');
  const [status, setStatus] = useState('');
  const [community, setCommunity] = useState(false);
  const [offset, setOffset] = useState(0);
  const [data, setData] = useState<AdminRestaurantsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setError(null);
    fetchAdminRestaurants({
      q: q || undefined,
      status: status || undefined,
      community,
      limit: PAGE_SIZE,
      offset,
    })
      .then((d) => {
        if (active) setData(d);
      })
      .catch((e: unknown) => {
        if (active) setError(friendlyAdminError(e));
      });
    return () => {
      active = false;
    };
  }, [q, status, community, offset]);

  return (
    <main data-testid="admin-restaurants">
      <h1 className="text-bw-2xl font-bold text-zinc-900">Restaurants</h1>

      <div className="mt-bw-4 flex flex-wrap items-center gap-bw-4 text-bw-sm">
        <input
          value={q}
          onChange={(e) => {
            setQ(e.target.value);
            setOffset(0);
          }}
          placeholder="Search name…"
          data-testid="restaurants-search"
          className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1"
        />
        <label className="flex items-center gap-bw-2 text-zinc-700">
          Status
          <select
            value={status}
            onChange={(e) => {
              setStatus(e.target.value);
              setOffset(0);
            }}
            data-testid="restaurants-status-filter"
            className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
          >
            <option value="">all</option>
            {STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </label>
        <label className="flex items-center gap-bw-2 text-zinc-700">
          <input
            type="checkbox"
            checked={community}
            onChange={(e) => {
              setCommunity(e.target.checked);
              setOffset(0);
            }}
            data-testid="restaurants-community-filter"
          />
          Community-published only
        </label>
      </div>

      {error && (
        <div role="alert" data-testid="restaurants-error" className="mt-bw-4 rounded border border-red-300 bg-red-50 p-4 text-red-900">
          {error}
        </div>
      )}

      {!data && !error && (
        <p role="status" className="mt-bw-4 text-bw-sm text-zinc-500">
          Loading restaurants…
        </p>
      )}

      {data && data.restaurants.length === 0 && (
        <p data-testid="restaurants-empty" className="mt-bw-6 text-bw-sm text-zinc-500">
          No restaurants match.
        </p>
      )}

      {data && data.restaurants.length > 0 && (
        <div className="mt-bw-4 space-y-bw-4">
          <ul className="space-y-bw-2">
            {data.restaurants.map((r) => (
              <li key={r.id} data-testid={`restaurant-row-${r.slug}`}>
                <Link
                  href={`/admin/restaurants/${r.id}`}
                  className="block rounded-bw-lg border border-zinc-200 bg-white p-bw-3 hover:border-bite"
                >
                  <div className="flex flex-wrap items-center justify-between gap-bw-2">
                    <span className="font-semibold text-zinc-900">{r.name}</span>
                    <span className="flex items-center gap-bw-2">
                      {(r.suggested_items_count ?? 0) > 0 && (
                        <StatusBadge
                          tone="warn"
                          label={`${r.suggested_items_count} awaiting graduation`}
                        />
                      )}
                      <StatusBadge label={r.status} tone={STATUS_TONES[r.status] ?? 'muted'} />
                    </span>
                  </div>
                  <p className="mt-bw-1 text-bw-xs text-zinc-500">
                    {r.city?.name ?? 'no city'} · {r.slug} · {r.items_count ?? 0} item
                    {(r.items_count ?? 0) === 1 ? '' : 's'}
                    {r.claimed_by_user_id && <> · claimed</>}
                  </p>
                </Link>
              </li>
            ))}
          </ul>
          <Pagination
            total={data.pagination.total}
            limit={data.pagination.limit}
            offset={data.pagination.offset}
            onOffset={setOffset}
          />
        </div>
      )}
    </main>
  );
}
