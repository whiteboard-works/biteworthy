'use client';

import { Suspense, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { fetchAdminRuns, type AdminRunRow, type AdminRunsResponse } from '../../../lib/admin/runs';
import { friendlyAdminError } from '../../../lib/admin/shared';
import { StatusBadge, type BadgeTone } from '../_StatusBadge';
import { Pagination } from '../_Pagination';

/**
 * /admin/runs — the cross-user moderation inbox. Filter state lives in
 * the URL (moderators share deep links); the community filter defaults
 * ON because admin-scanned runs rarely need review. Rows link into the
 * per-run review page.
 */

const STATUSES = ['queued', 'extracting', 'resolving', 'staged', 'published', 'failed'] as const;
const PAGE_SIZE = 25;

const STATUS_TONES: Record<string, BadgeTone> = {
  queued: 'muted',
  extracting: 'muted',
  resolving: 'muted',
  staged: 'warn',
  published: 'ok',
  failed: 'danger',
};

// Deploy-skew guard: a newer API introducing a status must not render
// an undefined tone.
function toneFor(status: AdminRunRow['status']): BadgeTone {
  return STATUS_TONES[status] ?? 'muted';
}

function RunsQueue() {
  const router = useRouter();
  const searchParams = useSearchParams();

  const status = searchParams.get('status') ?? '';
  // Default ON: absent param means "community only"; 'false' opts out.
  const community = searchParams.get('community') !== 'false';
  const offset = Math.max(0, Number(searchParams.get('offset')) || 0);

  const [data, setData] = useState<AdminRunsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setError(null);
    fetchAdminRuns({ status: status || undefined, community, limit: PAGE_SIZE, offset })
      .then((d) => {
        if (active) setData(d);
      })
      .catch((e: unknown) => {
        if (active) setError(friendlyAdminError(e));
      });
    return () => {
      active = false;
    };
  }, [status, community, offset]);

  const setQuery = (next: { status?: string; community?: boolean; offset?: number }) => {
    const params = new URLSearchParams();
    const s = next.status ?? status;
    const c = next.community ?? community;
    const o = next.offset ?? 0; // filter changes reset paging
    if (s) params.set('status', s);
    if (!c) params.set('community', 'false');
    if (o > 0) params.set('offset', String(o));
    const qs = params.toString();
    if (qs) {
      router.replace(`/admin/runs?${qs}`);
    } else {
      router.replace('/admin/runs');
    }
  };

  return (
    <main data-testid="admin-runs">
      <h1 className="text-bw-2xl font-bold text-zinc-900">Ingestion runs</h1>

      <div className="mt-bw-4 flex flex-wrap items-center gap-bw-4 text-bw-sm">
        <label className="flex items-center gap-bw-2 text-zinc-700">
          Status
          <select
            value={status}
            onChange={(e) => setQuery({ status: e.target.value })}
            data-testid="runs-status-filter"
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
            onChange={(e) => setQuery({ community: e.target.checked })}
            data-testid="runs-community-filter"
          />
          Community scans only
        </label>
      </div>

      {error && (
        <div
          role="alert"
          data-testid="runs-error"
          className="mt-bw-4 rounded border border-red-300 bg-red-50 p-4 text-red-900"
        >
          {error}
        </div>
      )}

      {!data && !error && (
        <p role="status" className="mt-bw-4 text-bw-sm text-zinc-500">
          Loading runs…
        </p>
      )}

      {data && data.runs.length === 0 && offset === 0 && (
        <p data-testid="runs-empty" className="mt-bw-6 text-bw-sm text-zinc-500">
          Nothing in the queue with these filters.
        </p>
      )}

      {/* A stale ?offset= deep link past the end must offer a way back —
          the pager hides itself when the queue fits on one page. */}
      {data && data.runs.length === 0 && offset > 0 && (
        <p data-testid="runs-past-end" className="mt-bw-6 text-bw-sm text-zinc-500">
          This page is past the end of the queue.{' '}
          <button
            type="button"
            onClick={() => setQuery({ offset: 0 })}
            data-testid="runs-back-to-start"
            className="font-semibold text-bite hover:text-bite-dark"
          >
            Back to the first page
          </button>
        </p>
      )}

      {data && data.runs.length > 0 && (
        <div className="mt-bw-4 space-y-bw-4">
          <ul className="space-y-bw-2">
            {data.runs.map((run) => (
              <RunRow key={run.id} run={run} />
            ))}
          </ul>
          <Pagination
            total={data.pagination.total}
            limit={data.pagination.limit}
            offset={data.pagination.offset}
            onOffset={(o) => setQuery({ offset: o })}
          />
        </div>
      )}
    </main>
  );
}

function RunRow({ run }: { run: AdminRunRow }) {
  const counts = run.decision_counts;
  const decided = counts.accepted + counts.rejected + counts.edited;
  const totalItems = decided + counts.pending;

  return (
    <li data-testid={`run-row-${run.id}`}>
      <Link
        href={`/admin/runs/${run.id}`}
        className="block rounded-bw-lg border border-zinc-200 bg-white p-bw-3 hover:border-bite"
      >
        <div className="flex flex-wrap items-center justify-between gap-bw-2">
          <span className="font-semibold text-zinc-900">
            {run.restaurant?.name ?? 'Unknown restaurant'}
          </span>
          <StatusBadge label={run.status} tone={toneFor(run.status)} />
        </div>
        <p className="mt-bw-1 text-bw-xs text-zinc-500">
          {run.user
            ? `by ${run.user.handle ?? run.user.email ?? 'unknown'}${
                run.user.handle && run.user.email ? ` (${run.user.email})` : ''
              }`
            : 'ownerless'}
          {run.created_at && <> · {new Date(run.created_at).toLocaleString()}</>}
          {run.input_kind && <> · {run.input_kind}</>}
          {run.api_cost_cents != null && <> · {(run.api_cost_cents / 100).toFixed(2)} USD</>}
        </p>
        <p className="mt-bw-1 text-bw-xs text-zinc-600">
          {totalItems === 0
            ? 'No staged items yet'
            : `${counts.pending} pending · ${counts.accepted} accepted · ${counts.rejected} rejected` +
              (counts.edited > 0 ? ` · ${counts.edited} edited` : '')}
        </p>
        {run.failure_message && (
          <p className="mt-bw-1 truncate text-bw-xs text-danger">{run.failure_message}</p>
        )}
      </Link>
    </li>
  );
}

export default function AdminRunsPage() {
  // useSearchParams needs a Suspense boundary even on a force-dynamic
  // segment; the fallback is invisible in practice.
  return (
    <Suspense fallback={null}>
      <RunsQueue />
    </Suspense>
  );
}
