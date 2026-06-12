'use client';

import { use, useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import {
  fetchRun,
  fetchRunItems,
  friendlyIngestionError,
  type IngestionItemPayload,
  type IngestionRunPayload,
} from '../../../../lib/ingestion';
import { VerifyItemRow } from './_VerifyItemRow';

const PIPELINE_LABELS: Record<IngestionRunPayload['status'], string> = {
  queued: 'Waiting in line…',
  extracting: 'Reading the menu…',
  resolving: 'Matching ingredients…',
  staged: 'Ready to verify',
  published: 'Published!',
  failed: 'Extraction failed',
};

const POLL_MS = 3_000;

/**
 * Phase 6.5 — web verify page. Polls the run while the pipeline is
 * working, then renders the staged items for accept/reject. The 80%
 * threshold (Phase 2.5) flips the run + restaurant to published as
 * decisions come in; we re-poll after each decision to notice.
 */
export default function VerifyRunPage({ params }: { params: Promise<{ runId: string }> }) {
  const { runId } = use(params);

  const [run, setRun] = useState<IngestionRunPayload | null>(null);
  const [items, setItems] = useState<IngestionItemPayload[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const pollTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const refresh = useCallback(async () => {
    try {
      const latest = await fetchRun(runId);
      setRun(latest);
      if (latest.status === 'staged' || latest.status === 'published') {
        setItems(await fetchRunItems(runId));
      } else if (latest.status !== 'failed') {
        pollTimer.current = setTimeout(() => void refresh(), POLL_MS);
      }
    } catch (e) {
      setError(friendlyIngestionError(e));
    }
  }, [runId]);

  useEffect(() => {
    void refresh();
    return () => {
      if (pollTimer.current) clearTimeout(pollTimer.current);
    };
  }, [refresh]);

  const onDecided = (updated: IngestionItemPayload) => {
    setItems((prev) => prev?.map((it) => (it.id === updated.id ? updated : it)) ?? null);
    // A decision may have crossed the 80% publish threshold.
    void fetchRun(runId).then(setRun).catch(() => undefined);
  };

  const decidedCount = items?.filter((it) => it.decision !== 'pending').length ?? 0;

  return (
    <main className="mx-auto max-w-3xl space-y-6 p-6">
      <header>
        <p className="text-sm font-semibold uppercase tracking-widest text-orange-600">
          Verify the scan
        </p>
        <h1 className="mt-1 text-3xl font-bold">
          {run ? PIPELINE_LABELS[run.status] : 'Loading…'}
        </h1>
        {run && run.status !== 'staged' && run.status !== 'published' && run.status !== 'failed' && (
          <p className="mt-2 text-zinc-600" role="status">
            This usually takes under a minute. The page refreshes itself.
          </p>
        )}
        {run?.status === 'failed' && (
          <p className="mt-2 text-red-700" role="alert">
            {run.failure_message ?? 'Something went wrong during extraction.'}
          </p>
        )}
      </header>

      {run?.status === 'published' && (
        <div className="rounded-xl border border-green-300 bg-green-50 p-4 text-green-900" role="status">
          <p className="font-semibold">This menu is live! 🎉</p>
          <p className="mt-1 text-sm">
            <Link href={`/restaurants/${run.restaurant_id}`} className="underline">
              See the restaurant page
            </Link>{' '}
            — items you verified show for everyone (strict-mode users see them once an
            admin confirms).
          </p>
        </div>
      )}

      {items && (
        <>
          <p className="text-sm text-zinc-500" role="status">
            {decidedCount} of {items.length} decided — accept at least 80% to publish.
          </p>
          <ul className="space-y-3">
            {items.map((item) => (
              <VerifyItemRow key={item.id} runId={runId} item={item} onDecided={onDecided} />
            ))}
          </ul>
        </>
      )}

      {error && (
        <div className="rounded border border-red-300 bg-red-50 p-4 text-red-900" role="alert">
          {error}
        </div>
      )}
    </main>
  );
}
