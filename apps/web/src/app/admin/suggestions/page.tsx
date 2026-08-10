'use client';

import { useEffect, useState } from 'react';
import {
  fetchAdminSuggestions,
  type AdminSuggestionRow,
  type AdminSuggestionsResponse,
} from '../../../lib/admin/suggestions';
import { friendlyAdminError } from '../../../lib/admin/shared';
import { destroyAdminSuggestion } from '../../../lib/admin/deletes';
import { decideSuggestion, SuggestionError } from '../../../lib/suggestions';
import { HardDeleteButton } from '../_HardDeleteButton';
import { Pagination } from '../_Pagination';

/**
 * /admin/suggestions — the cross-restaurant pending queue (the owner
 * queue only covers claimed restaurants; most aren't). Accept/reject
 * reuses the owner-queue endpoint; a decided row leaves the queue.
 */

const PAGE_SIZE = 25;

export default function AdminSuggestionsPage() {
  const [offset, setOffset] = useState(0);
  const [refreshKey, setRefreshKey] = useState(0);
  const [data, setData] = useState<AdminSuggestionsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setError(null);
    fetchAdminSuggestions({ limit: PAGE_SIZE, offset })
      .then((d) => {
        if (!active) return;
        // Deciding rows shifts server offsets; a page that emptied out
        // while the queue still has entries must snap back rather than
        // show a false "Inbox zero".
        if (d.suggestions.length === 0 && offset > 0 && d.pagination.total > 0) {
          setOffset(0);
          return;
        }
        setData(d);
      })
      .catch((e: unknown) => {
        if (active) setError(friendlyAdminError(e));
      });
    return () => {
      active = false;
    };
  }, [offset, refreshKey]);

  // Refetch rather than filter, for the reason `decide` gives below:
  // local removal lies once a page empties or rows slide across the
  // offset window.
  const dropRow = () => setRefreshKey((k) => k + 1);

  const decide = async (id: string, decision: 'accepted' | 'rejected') => {
    setBusyId(id);
    setError(null);
    try {
      await decideSuggestion(id, decision);
      // Refetch instead of filtering locally — local removal lies once
      // a page empties or rows slide across the offset window.
      setRefreshKey((k) => k + 1);
    } catch (e) {
      if (e instanceof SuggestionError && e.status === 401) {
        setError('You are signed out — sign in again to continue.');
      } else if (e instanceof SuggestionError && (e.status === 403 || e.status === 404)) {
        setError('Admin access is gone — your account may have been changed.');
      } else {
        setError(friendlyAdminError(e));
      }
    } finally {
      // Only clear our own marker — a concurrent decide on another row
      // must keep its busy state.
      setBusyId((cur) => (cur === id ? null : cur));
    }
  };

  return (
    <main data-testid="admin-suggestions">
      <h1 className="text-bw-2xl font-bold text-zinc-900">Suggestions</h1>
      <p className="mt-bw-2 text-bw-sm text-zinc-500">
        Pending community fixes across every restaurant, oldest first. Accepting materializes the
        change immediately.
      </p>

      {error && (
        <div
          role="alert"
          data-testid="suggestions-error"
          className="mt-bw-4 rounded border border-red-300 bg-red-50 p-4 text-red-900"
        >
          {error}
        </div>
      )}

      {!data && !error && (
        <p role="status" className="mt-bw-4 text-bw-sm text-zinc-500">
          Loading suggestions…
        </p>
      )}

      {data && data.suggestions.length === 0 && (
        <p data-testid="suggestions-empty" className="mt-bw-6 text-bw-sm text-zinc-500">
          No pending suggestions. Inbox zero.
        </p>
      )}

      {data && data.suggestions.length > 0 && (
        <div className="mt-bw-4 space-y-bw-4">
          <ul className="space-y-bw-3">
            {data.suggestions.map((s) => (
              <SuggestionRow
                key={s.id}
                suggestion={s}
                busy={busyId === s.id}
                onDecide={decide}
                onDeleted={dropRow}
              />
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

function SuggestionRow({
  suggestion,
  busy,
  onDecide,
  onDeleted,
}: {
  suggestion: AdminSuggestionRow;
  busy: boolean;
  onDecide: (id: string, decision: 'accepted' | 'rejected') => void;
  onDeleted: (id: string) => void;
}) {
  // A confirmed delete must take Accept and Reject with it — otherwise
  // a click lands on a row already being destroyed.
  const [deleting, setDeleting] = useState(false);
  const inert = busy || deleting;

  return (
    <li
      data-testid={`admin-suggestion-${suggestion.id}`}
      className="rounded-bw-lg border border-zinc-200 bg-white p-bw-4"
    >
      <p className="text-bw-sm font-semibold text-zinc-700">
        {suggestion.kind} on{' '}
        <span className="text-zinc-900">{suggestion.item?.name ?? 'unknown item'}</span>
        {suggestion.submitter?.handle && (
          <span className="font-normal text-zinc-500"> · by {suggestion.submitter.handle}</span>
        )}
      </p>
      <pre className="mt-bw-1 overflow-x-auto rounded-bw-md bg-zinc-50 p-bw-2 text-bw-xs text-zinc-700">
        {JSON.stringify(suggestion.payload, null, 2)}
      </pre>
      <div className="mt-bw-2 flex items-center gap-bw-2 text-bw-sm">
        <button
          type="button"
          onClick={() => onDecide(suggestion.id, 'accepted')}
          disabled={inert}
          data-testid={`admin-suggestion-accept-${suggestion.id}`}
          className="rounded-bw-md bg-ok px-bw-3 py-bw-1 font-semibold text-white disabled:opacity-50"
        >
          Accept
        </button>
        <button
          type="button"
          onClick={() => onDecide(suggestion.id, 'rejected')}
          disabled={inert}
          data-testid={`admin-suggestion-reject-${suggestion.id}`}
          className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1 font-semibold text-zinc-700 hover:border-danger hover:text-danger disabled:opacity-50"
        >
          Reject
        </button>
        {/* Rejecting keeps the suggestion legible to the member who
            filed it and records who resolved it. Delete is for spam
            and mistakes — nothing to keep, nobody to answer. */}
        <HardDeleteButton
          onDelete={() => destroyAdminSuggestion(suggestion.id)}
          onDeleted={() => onDeleted(suggestion.id)}
          onBusyChange={setDeleting}
          disabled={busy}
          testId={`admin-suggestion-delete-${suggestion.id}`}
        />
      </div>
    </li>
  );
}
