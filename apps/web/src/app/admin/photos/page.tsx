'use client';

import { useEffect, useState } from 'react';
import {
  approvePhotoSubmission,
  fetchPhotoSubmissions,
  PHOTO_STATUSES,
  REJECT_REASONS,
  rejectPhotoSubmission,
  type AdminPhotoSubmissionsResponse,
  type PhotoQueueStatus,
  type PhotoRejectReason,
} from '../../../lib/admin/photo-submissions';
import { friendlyAdminError } from '../../../lib/admin/shared';
import { Pagination } from '../_Pagination';
import { StatusBadge } from '../_StatusBadge';

const PAGE_SIZE = 25;

export default function AdminPhotosPage() {
  const [status, setStatus] = useState<PhotoQueueStatus>('pending');
  const [offset, setOffset] = useState(0);
  const [data, setData] = useState<AdminPhotoSubmissionsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    let active = true;
    setError(null);
    fetchPhotoSubmissions({ status, limit: PAGE_SIZE, offset })
      .then((d) => {
        if (active) setData(d);
      })
      .catch((e: unknown) => {
        if (active) setError(friendlyAdminError(e));
      });
    return () => {
      active = false;
    };
  }, [status, offset, refreshKey]);

  return (
    <main data-testid="admin-photos">
      <h1 className="text-bw-2xl font-bold text-zinc-900">Dish photos</h1>
      <p className="mt-bw-2 text-bw-sm text-zinc-600">
        Diners submit these. Approve-and-set copies the image onto the dish; approve without
        replacing keeps the current photo when the dish already has one.
      </p>

      <div className="mt-bw-4 flex flex-wrap items-center gap-bw-2 text-bw-sm">
        {PHOTO_STATUSES.map((s) => (
          <button
            key={s}
            type="button"
            aria-pressed={status === s}
            onClick={() => {
              setStatus(s);
              setOffset(0);
              setData(null);
            }}
            data-testid={`photos-status-${s}`}
            className={
              status === s
                ? 'rounded-bw-pill bg-bite px-bw-3 py-bw-1 font-semibold text-white'
                : 'rounded-bw-pill border border-zinc-300 px-bw-3 py-bw-1 font-semibold text-zinc-600 hover:border-bite hover:text-bite'
            }
          >
            {s}
          </button>
        ))}
      </div>

      {error && (
        <div
          role="alert"
          data-testid="photos-error"
          className="mt-bw-4 rounded border border-red-300 bg-red-50 p-4 text-red-900"
        >
          {error}
        </div>
      )}

      {!data && !error && (
        <p role="status" className="mt-bw-4 text-bw-sm text-zinc-500">
          Loading photos…
        </p>
      )}

      {data && data.photo_submissions.length === 0 && (
        <p data-testid="photos-empty" className="mt-bw-6 text-bw-sm text-zinc-500">
          {status === 'pending' ? 'No pending dish photos. Inbox zero.' : 'Nothing here.'}
        </p>
      )}

      {data && data.photo_submissions.length > 0 && (
        <div className="mt-bw-4 space-y-bw-4">
          <ul className="space-y-bw-3">
            {data.photo_submissions.map((row) => (
              <PhotoModRow
                key={row.id}
                row={row}
                onChanged={() => setRefreshKey((k) => k + 1)}
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

function PhotoModRow({
  row,
  onChanged,
}: {
  row: AdminPhotoSubmissionsResponse['photo_submissions'][number];
  onChanged: () => void;
}) {
  const [reason, setReason] = useState<PhotoRejectReason>('low_quality');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const hasCurrentPhoto = Boolean(row.item?.photo_url);
  const pending = row.status === 'pending';

  const act = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
      onChanged();
    } catch (e) {
      setError(friendlyAdminError(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <li
      data-testid={`photo-mod-${row.id}`}
      className="rounded-bw-lg border border-zinc-200 bg-white p-bw-3"
    >
      <div className="flex flex-wrap items-start justify-between gap-bw-2">
        <div className="min-w-0">
          <p className="text-bw-sm text-zinc-500">
            <span className="font-semibold text-zinc-900">
              {row.user?.display_name || row.user?.handle || row.credit_name}
            </span>{' '}
            on <span className="font-semibold text-zinc-900">{row.item?.name ?? '—'}</span>
            {row.item?.restaurant?.name && <> at {row.item.restaurant.name}</>}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-bw-2">
          {!hasCurrentPhoto && (
            <span
              data-testid={`photo-no-current-${row.id}`}
              className="rounded-bw-pill bg-zinc-100 px-bw-2 py-0.5 text-bw-xs font-semibold text-zinc-600"
            >
              No dish photo
            </span>
          )}
          <StatusBadge
            tone={
              row.status === 'approved' || row.status === 'approve_keep'
                ? 'ok'
                : row.status === 'rejected'
                  ? 'danger'
                  : 'warn'
            }
            label={row.status === 'rejected' ? `rejected: ${row.rejection_reason ?? '?'}` : row.status}
          />
        </div>
      </div>

      <div className="mt-bw-2 flex items-start gap-bw-3">
        {row.photo_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={row.photo_url}
            alt="Submitted dish photo"
            className="h-20 w-20 shrink-0 rounded-bw-md object-cover"
          />
        ) : (
          <div className="flex h-20 w-20 shrink-0 items-center justify-center rounded-bw-md bg-zinc-100 text-bw-xs text-zinc-500">
            Gone
          </div>
        )}
        {hasCurrentPhoto ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={row.item!.photo_url!}
            alt="Current dish photo"
            className="h-20 w-20 shrink-0 rounded-bw-md object-cover"
          />
        ) : null}
      </div>

      {pending && (
        <div className="mt-bw-3 flex flex-wrap items-center gap-bw-2 text-bw-sm">
          <button
            type="button"
            onClick={() => void act(() => approvePhotoSubmission(row.id, true))}
            disabled={busy}
            data-testid={`photo-approve-set-${row.id}`}
            className="rounded-bw-md bg-bite px-bw-3 py-bw-1 font-semibold text-white disabled:opacity-50"
          >
            {busy ? 'Saving…' : 'Approve and set as dish photo'}
          </button>
          {hasCurrentPhoto && (
            <button
              type="button"
              onClick={() => void act(() => approvePhotoSubmission(row.id, false))}
              disabled={busy}
              data-testid={`photo-approve-keep-${row.id}`}
              className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1 font-semibold text-zinc-700 hover:border-ok hover:text-ok disabled:opacity-50"
            >
              Approve without replacing
            </button>
          )}
          <label className="flex items-center gap-bw-2 text-zinc-600">
            Reason
            <select
              value={reason}
              onChange={(e) => setReason(e.target.value as PhotoRejectReason)}
              data-testid={`photo-reason-${row.id}`}
              className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
            >
              {REJECT_REASONS.map((r) => (
                <option key={r} value={r}>
                  {r.replaceAll('_', ' ')}
                </option>
              ))}
            </select>
          </label>
          <button
            type="button"
            onClick={() => void act(() => rejectPhotoSubmission(row.id, reason))}
            disabled={busy}
            data-testid={`photo-reject-${row.id}`}
            className="rounded-bw-md bg-danger px-bw-3 py-bw-1 font-semibold text-white disabled:opacity-50"
          >
            Reject
          </button>
        </div>
      )}

      {error && (
        <p role="alert" className="mt-bw-2 text-bw-sm text-red-700">
          {error}
        </p>
      )}
    </li>
  );
}
