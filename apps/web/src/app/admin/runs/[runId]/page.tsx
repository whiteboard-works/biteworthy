'use client';

import { use, useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import {
  acceptAllRunItems,
  fetchRun,
  fetchRunItems,
  friendlyIngestionError,
  type IngestionItemPayload,
  type IngestionRunPayload,
} from '../../../../lib/ingestion';
import { confirmCommunity, reExtractRun } from '../../../../lib/admin/runs';
import { AdminError, friendlyAdminError } from '../../../../lib/admin/shared';
import { VerifyItemRow } from '../../../ingest/verify/[runId]/_VerifyItemRow';
import { ConfirmButton } from '../../_ConfirmButton';
import { StatusBadge } from '../../_StatusBadge';

/**
 * /admin/runs/[runId] — per-run moderation. Item review reuses the
 * verify machinery verbatim (same endpoints, same VerifyItemRow —
 * an admin's accepts land confidence: confirmed server-side); this
 * page adds the two admin-only levers: re-extract and the
 * confirm-community graduation. No polling — admins review settled
 * runs; Refresh covers the rest.
 */

const RE_EXTRACT_ERRORS: Record<string, string> = {
  already_published: 'This run is published — its items are live.',
  has_promoted_items: 'Undo the accepted items first — re-extracting would orphan them.',
};

export default function AdminRunPage({ params }: { params: Promise<{ runId: string }> }) {
  const { runId } = use(params);

  const [run, setRun] = useState<IngestionRunPayload | null>(null);
  const [items, setItems] = useState<IngestionItemPayload[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<'accept_all' | 're_extract' | 'confirm' | null>(null);
  const [confirmResult, setConfirmResult] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setError(null);
    try {
      const latest = await fetchRun(runId);
      setRun(latest);
      if (['resolving', 'staged', 'published'].includes(latest.status)) {
        setItems(await fetchRunItems(runId));
      } else {
        setItems(null);
      }
    } catch (e) {
      setError(friendlyIngestionError(e));
    }
  }, [runId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const onDecided = (updated: IngestionItemPayload) => {
    setItems((prev) => prev?.map((it) => (it.id === updated.id ? updated : it)) ?? null);
    void fetchRun(runId).then(setRun).catch(() => undefined);
  };

  const onAcceptAll = async () => {
    setBusy('accept_all');
    setError(null);
    try {
      setItems(await acceptAllRunItems(runId));
      setRun(await fetchRun(runId));
    } catch (e) {
      setError(friendlyIngestionError(e));
    } finally {
      setBusy(null);
    }
  };

  const onReExtract = async () => {
    setBusy('re_extract');
    setError(null);
    try {
      await reExtractRun(runId);
      await refresh();
    } catch (e) {
      const code = e instanceof AdminError ? e.code : undefined;
      setError((code && RE_EXTRACT_ERRORS[code]) ?? friendlyAdminError(e));
    } finally {
      setBusy(null);
    }
  };

  const onConfirmCommunity = async () => {
    if (!run) return;
    setBusy('confirm');
    setError(null);
    setConfirmResult(null);
    try {
      const res = await confirmCommunity(run.restaurant_id);
      setConfirmResult(
        `Confirmed ${res.confirmed.items} item(s), ${res.confirmed.ingredients} ingredient link(s), ` +
          `${res.confirmed.tags} tag link(s) — strict-mode users can now see them.`,
      );
      await refresh();
    } catch (e) {
      setError(friendlyAdminError(e));
    } finally {
      setBusy(null);
    }
  };

  const enriched = run?.status === 'staged' || run?.status === 'published';
  const enriching = enriched && run?.enrichment_status === 'pending';
  const pendingCount = items?.filter((it) => it.decision === 'pending').length ?? 0;

  return (
    <main data-testid="admin-run-detail" className="space-y-bw-6">
      <header className="flex flex-wrap items-center justify-between gap-bw-3">
        <div>
          <Link href="/admin/runs" className="text-bw-xs font-semibold text-zinc-500 hover:text-bite">
            ← All runs
          </Link>
          <h1 className="mt-bw-1 flex items-center gap-bw-3 text-bw-2xl font-bold text-zinc-900">
            Run review
            {run && <StatusBadge label={run.status} tone={run.status === 'failed' ? 'danger' : 'muted'} />}
          </h1>
          {run?.failure_message && (
            <p className="mt-bw-1 text-bw-sm text-danger" role="alert">
              {run.failure_message}
            </p>
          )}
        </div>
        <div className="flex items-center gap-bw-3">
          <button
            type="button"
            onClick={() => void refresh()}
            data-testid="run-refresh"
            className="text-bw-sm font-semibold text-zinc-600 hover:text-bite"
          >
            Refresh
          </button>
          <ConfirmButton
            label="Re-extract"
            confirmLabel="Confirm — wipe staged cards and re-extract"
            busy={busy === 're_extract'}
            onConfirm={() => void onReExtract()}
            testId="run-re-extract"
          />
        </div>
      </header>

      {run && (
        <section
          data-testid="confirm-community-panel"
          className="flex flex-wrap items-center justify-between gap-bw-3 rounded-bw-lg border border-zinc-200 bg-white p-bw-4"
        >
          <div className="text-bw-sm text-zinc-700">
            <p className="font-semibold text-zinc-900">Strict-mode graduation</p>
            <p className="mt-bw-1 text-bw-xs text-zinc-500">
              Confirms this restaurant&rsquo;s community-verified data so strict (allergy) users see
              it. Only items whose every association is confirmed graduate.
            </p>
            {confirmResult && (
              <p role="status" data-testid="confirm-community-result" className="mt-bw-1 text-ok">
                {confirmResult}
              </p>
            )}
          </div>
          <ConfirmButton
            label="Confirm community menu"
            busy={busy === 'confirm'}
            onConfirm={() => void onConfirmCommunity()}
            testId="confirm-community"
          />
        </section>
      )}

      {error && (
        <div role="alert" data-testid="run-error" className="rounded border border-red-300 bg-red-50 p-4 text-red-900">
          {error}
        </div>
      )}

      {!run && !error && (
        <p role="status" className="text-bw-sm text-zinc-500">
          Loading run…
        </p>
      )}

      {run && !items && !error && (
        <p role="status" className="text-bw-sm text-zinc-500">
          No reviewable items yet — the run is {run.status}. Refresh once extraction finishes.
        </p>
      )}

      {items && items.length > 0 && (
        <>
          <div className="flex flex-wrap items-center justify-between gap-bw-3 rounded-bw-lg border border-zinc-200 bg-zinc-50 p-bw-3 text-bw-sm">
            <span role="status" className="text-zinc-600">
              <span className="font-semibold text-zinc-900">{items.length} dishes</span> ·{' '}
              {pendingCount} pending
              {enriching && ' · AI double-check still running'}
            </span>
            {pendingCount > 0 && (
              <button
                type="button"
                onClick={() => void onAcceptAll()}
                disabled={busy === 'accept_all'}
                data-testid="admin-accept-all"
                className="rounded-bw-md bg-ok px-bw-3 py-bw-1 font-semibold text-white disabled:opacity-50"
              >
                {busy === 'accept_all' ? 'Accepting…' : `Accept all ${pendingCount}`}
              </button>
            )}
          </div>

          <ul className="space-y-bw-3">
            {items.map((it) => (
              <VerifyItemRow
                key={it.id}
                runId={runId}
                item={it}
                enriched={Boolean(enriched)}
                enriching={Boolean(enriching)}
                onDecided={onDecided}
              />
            ))}
          </ul>
        </>
      )}
    </main>
  );
}
