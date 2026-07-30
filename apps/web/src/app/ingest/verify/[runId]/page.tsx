'use client';

import { use, useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import {
  acceptAllRunItems,
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
  resolving: 'Dishes found — matching ingredients…',
  staged: 'Ready to verify',
  published: 'Published!',
  failed: 'Extraction failed',
};

const POLL_MS = 3_000;

// Group items by sub-menu (section), preserving first-seen (menu) order; items
// with no section land under a neutral "Menu" header.
function groupBySection(
  items: IngestionItemPayload[],
): Array<[string, IngestionItemPayload[]]> {
  const groups = new Map<string, IngestionItemPayload[]>();
  for (const it of items) {
    const key = it.section_name?.trim() || 'Menu';
    const arr = groups.get(key) ?? [];
    arr.push(it);
    groups.set(key, arr);
  }
  return [...groups.entries()];
}

/**
 * Verify page (verify-flow redesign). Dishes are materialized at extraction, so
 * they show up during `:resolving` — grouped by sub-menu, each with its
 * ingredient/tag chips "matching…" until enrichment lands. Accept / Reject /
 * Undo per dish, plus Accept All. Publishing only fires once matching finishes
 * (`:staged`), so a dish never goes live without its allergen data.
 */
export default function VerifyRunPage({ params }: { params: Promise<{ runId: string }> }) {
  const { runId } = use(params);

  const [run, setRun] = useState<IngestionRunPayload | null>(null);
  const [items, setItems] = useState<IngestionItemPayload[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [acceptingAll, setAcceptingAll] = useState(false);
  const pollTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const refresh = useCallback(async () => {
    try {
      const latest = await fetchRun(runId);
      setRun(latest);
      // Dishes exist from :resolving on — show them (and keep them fresh as
      // enrichment fills in), not just at :staged.
      if (['resolving', 'staged', 'published'].includes(latest.status)) {
        setItems(await fetchRunItems(runId));
      }
      // Keep polling until the run terminates AND the background AI
      // gap-fill pass has settled (the run stages on deterministic
      // matches; enrichment may still be appending suggestions).
      const settled =
        latest.status === 'failed' ||
        (['staged', 'published'].includes(latest.status) &&
          latest.enrichment_status !== 'pending');
      if (!settled) {
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

  const onAcceptAll = async () => {
    setError(null);
    try {
      setAcceptingAll(true);
      setItems(await acceptAllRunItems(runId));
      await fetchRun(runId).then(setRun);
    } catch (e) {
      setError(friendlyIngestionError(e));
    } finally {
      setAcceptingAll(false);
    }
  };

  const enriched = run?.status === 'staged' || run?.status === 'published';
  const enriching = enriched && run?.enrichment_status === 'pending';
  const decidedCount = items?.filter((it) => it.decision !== 'pending').length ?? 0;
  const pendingCount = items?.filter((it) => it.decision === 'pending').length ?? 0;
  const stillWorking = run != null && ['queued', 'extracting', 'resolving'].includes(run.status);

  return (
    <main className="mx-auto max-w-3xl space-y-6 p-6">
      <header>
        <p className="text-sm font-semibold uppercase tracking-widest text-orange-600">
          Verify the scan
        </p>
        <h1 className="mt-1 text-3xl font-bold">
          {run ? PIPELINE_LABELS[run.status] : 'Loading…'}
        </h1>
        {stillWorking && !items && (
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

      {items && items.length > 0 && (
        <>
          <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-zinc-200 bg-zinc-50 p-4">
            <div className="text-sm text-zinc-600" role="status">
              <span className="font-semibold text-zinc-900">{items.length} dishes</span>
              {!enriched && <span className="text-zinc-500"> · still matching ingredients &amp; tags…</span>}
              {enriching && (
                <span className="text-zinc-500"> · AI double-check still running for some dishes…</span>
              )}
              <span className="mt-1 block">
                {decidedCount} of {items.length} decided — accept at least 80% to publish
                {!enriched && ' (publishing finalizes once matching finishes)'}.
              </span>
            </div>
            {pendingCount > 0 && (
              <button
                type="button"
                onClick={() => void onAcceptAll()}
                disabled={acceptingAll}
                data-testid="accept-all"
                className="shrink-0 rounded bg-green-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
              >
                {acceptingAll ? 'Accepting…' : `Accept all ${pendingCount}`}
              </button>
            )}
          </div>

          {groupBySection(items).map(([section, sectionItems]) => (
            <section key={section} className="space-y-3" data-testid={`verify-section-${section}`}>
              <h2 className="text-xs font-bold uppercase tracking-wide text-zinc-400">{section}</h2>
              <ul className="space-y-3">
                {sectionItems.map((it) => (
                  <VerifyItemRow
                    key={it.id}
                    runId={runId}
                    item={it}
                    enriched={enriched}
                    enriching={enriching}
                    onDecided={onDecided}
                  />
                ))}
              </ul>
            </section>
          ))}
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
