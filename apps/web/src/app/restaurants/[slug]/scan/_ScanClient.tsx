'use client';

import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import type { Route } from 'next';
import { useRouter } from 'next/navigation';
import {
  acceptScan,
  getScan,
  rejectScan,
  NotSignedInError,
  ScanError,
  startScan,
  uploadAttachment,
  type ScanDish,
} from '../../../../lib/scans';

/**
 * Photo or link → progress → review → on the menu.
 *
 * The chat can do all of this too, but here checking progress is a row
 * read every few seconds rather than a model round, and the person lands
 * on the filtered menu the moment they accept.
 */

// Extraction is 20–60 s. Every web user's polls share one per-IP API
// budget (the Next proxy is the client Rails sees), so poll gently and
// back off hard on errors — a 429 above all.
const POLL_MS = 4000;
// Well past the client's own 240 s read timeout and its retries; a scan
// still "extracting" after this is stuck, not slow.
const GIVE_UP_MS = 5 * 60 * 1000;
// The ingredient pass stays `pending` through its job's retries (each call
// can run minutes), and only says `failed` once they're spent.
const ENRICHMENT_GIVE_UP_MS = 20 * 60 * 1000;
// A dropped poll on a phone at a table is normal. After this many in a
// row, stop polling — but keep the scan: it is paid for and still running.
const MAX_POLL_MISSES = 4;
// The scan door's default batch limits (Ingestion::StartRun), checked
// before anything uploads so a doomed batch doesn't spend the uploads.
// The server stays the authority; this only saves the round trips.
const MAX_FILES = 10;
const MAX_TOTAL_BYTES = 20 * 1024 * 1024;

type Phase =
  | { kind: 'pick' }
  | { kind: 'starting' }
  | { kind: 'scanning'; scanId: string; startedAt: number }
  | { kind: 'lost'; scanId: string; message: string }
  | { kind: 'review'; scanId: string; dishes: ScanDish[]; enrichmentFailed: boolean }
  | { kind: 'accepting'; scanId: string; dishes: ScanDish[]; enrichmentFailed: boolean }
  | { kind: 'done'; message: string };

export function ScanClient({
  slug,
  restaurantName,
  resumeScanId = null,
}: {
  slug: string;
  restaurantName: string;
  /** From `?scan=` — a paid scan survives a refresh or an evicted tab. */
  resumeScanId?: string | null;
}) {
  const router = useRouter();
  const scanPath = `/restaurants/${encodeURIComponent(slug)}/scan` as Route;
  // A finished scan leaves the URL, so a refresh starts fresh instead of
  // reopening a scan with nothing left to decide.
  const finish = (message: string) => {
    router.replace(scanPath);
    setPhase({ kind: 'done', message });
  };
  const [phase, setPhase] = useState<Phase>(() =>
    resumeScanId
      ? { kind: 'scanning', scanId: resumeScanId, startedAt: Date.now() }
      : { kind: 'pick' },
  );
  const [error, setError] = useState<string | null>(null);

  const fail = (e: unknown) => {
    if (e instanceof NotSignedInError) {
      const scanId = 'scanId' in phase ? phase.scanId : null;
      const here = `/restaurants/${slug}/scan${scanId ? `?scan=${encodeURIComponent(scanId)}` : ''}`;
      router.replace(`/login?next=${encodeURIComponent(here)}`);
      return;
    }
    setError(e instanceof Error ? e.message : 'Something went wrong.');
  };

  const begin = async (files: File[], url: string) => {
    setError(null);
    setPhase({ kind: 'starting' });
    try {
      const source =
        files.length > 0 ? { attachmentIds: await uploadInOrder(files) } : { sourceUrl: url };
      const started = await startScan(slug, source);
      // In the URL so a refresh, a backgrounded tab or a login bounce comes
      // back to this scan instead of a fresh (and re-billed) one.
      router.replace(
        `/restaurants/${encodeURIComponent(slug)}/scan?scan=${encodeURIComponent(started.scan_id)}`,
      );
      setPhase({ kind: 'scanning', scanId: started.scan_id, startedAt: Date.now() });
    } catch (e) {
      setPhase({ kind: 'pick' });
      fail(e);
    }
  };

  const publish = async (
    scanId: string,
    dishes: ScanDish[],
    enrichmentFailed: boolean,
    { accept, reject }: Decisions,
  ) => {
    setError(null);
    setPhase({ kind: 'accepting', scanId, dishes, enrichmentFailed });
    try {
      // Rejections first: the draft-publish threshold is computed when the
      // accept lands, and it should count what the person turned down.
      if (reject.length > 0) await rejectScan(scanId, reject);
      if (accept.length === 0) {
        finish(
          `Discarded ${reject.length} dish${reject.length === 1 ? '' : 'es'}. Nothing was added to the menu.`,
        );
        return;
      }
      const result = await acceptScan(scanId, accept);
      // Each dish publishes independently, so a 200 can still carry
      // failures. Keep those on screen, still ticked, for another try.
      const failedIds = new Set((result.failed ?? []).map((f) => f.id));
      if (failedIds.size > 0) {
        const failed = dishes.filter((d) => failedIds.has(d.id));
        setPhase({ kind: 'review', scanId, dishes: failed, enrichmentFailed });
        setError(
          `Couldn't add ${failed.map((d) => d.name).join(', ') || 'some dishes'}. Try again.`,
        );
        return;
      }
      // A draft restaurant publishes once 80% of the *decided* dishes are
      // accepted (IngestionRun#maybe_publish!). Below that its page 404s, so
      // don't send them there.
      if (!result.restaurant_published) {
        finish(
          "Saved. This restaurant isn't public yet — too many of its dishes have been turned down so far. Its menu goes live once most of the reviewed dishes are accepted.",
        );
        return;
      }
      router.push(`/restaurants/${encodeURIComponent(slug)}`);
      router.refresh();
    } catch (e) {
      // The rejections may have landed before the accept failed. Re-read
      // the scan so a retry shows current decisions — never a discarded
      // dish ticked again.
      const fresh = await getScan(scanId).catch(() => null);
      // A dropped response can hide an accept that committed. If none of
      // the requested dishes is still pending, it landed — finish.
      const stillPending = new Set(
        (fresh?.dishes ?? []).filter((d) => d.decision === 'pending').map((d) => d.id),
      );
      if (fresh?.dishes && accept.length > 0 && accept.every((id) => !stillPending.has(id))) {
        if (fresh.status === 'published') {
          router.push(`/restaurants/${encodeURIComponent(slug)}`);
          router.refresh();
        } else {
          finish('Saved.');
        }
        return;
      }
      setPhase({ kind: 'review', scanId, dishes: fresh?.dishes ?? dishes, enrichmentFailed });
      fail(e);
    }
  };

  return (
    <main className="mx-auto max-w-3xl px-bw-6 py-bw-12">
      <p className="text-bw-sm font-semibold uppercase tracking-wider text-bite">Add a menu</p>
      <h1 className="mt-bw-2 text-bw-3xl font-bold">{restaurantName}</h1>

      {error && (
        <p
          role="alert"
          className="mt-bw-4 rounded-bw-md bg-danger/10 px-bw-3 py-bw-2 text-bw-sm text-danger"
        >
          {error}
        </p>
      )}

      {(phase.kind === 'pick' || phase.kind === 'starting') && (
        <PickSource busy={phase.kind === 'starting'} onSubmit={begin} />
      )}
      {phase.kind === 'scanning' && (
        <Progress
          scanId={phase.scanId}
          startedAt={phase.startedAt}
          slug={slug}
          onReady={(dishes, enrichmentFailed) =>
            setPhase({ kind: 'review', scanId: phase.scanId, dishes, enrichmentFailed })
          }
          onFail={(message) => {
            router.replace(scanPath);
            setPhase({ kind: 'pick' });
            setError(message);
          }}
          onLost={(message) => setPhase({ kind: 'lost', scanId: phase.scanId, message })}
          onError={fail}
        />
      )}
      {phase.kind === 'lost' && (
        <div className="mt-bw-6 rounded-bw-lg bg-bite-light p-bw-6 text-center" role="alert">
          <p className="text-bw-base text-bite-dark">{phase.message}</p>
          <button
            type="button"
            onClick={() =>
              setPhase({ kind: 'scanning', scanId: phase.scanId, startedAt: Date.now() })
            }
            className="mt-bw-3 rounded-bw-md bg-bite px-bw-6 py-bw-2 text-bw-base font-bold text-white hover:bg-bite-dark"
          >
            Keep waiting
          </button>
        </div>
      )}
      {phase.kind === 'done' && (
        <p className="mt-bw-6 rounded-bw-lg bg-bite-light p-bw-6 text-bw-base text-bite-dark">
          {phase.message}
        </p>
      )}
      {(phase.kind === 'review' || phase.kind === 'accepting') && (
        <Review
          // A new dish list (after a partial failure) starts with every
          // remaining dish ticked, not the previous selection.
          key={phase.dishes.map((d) => d.id).join()}
          dishes={phase.dishes}
          enrichmentFailed={phase.enrichmentFailed}
          busy={phase.kind === 'accepting'}
          onSubmit={(decisions) =>
            publish(phase.scanId, phase.dishes, phase.enrichmentFailed, decisions)
          }
          onScanAnother={() => {
            router.replace(scanPath);
            setPhase({ kind: 'pick' });
          }}
        />
      )}
    </main>
  );
}

function PickSource({
  busy,
  onSubmit,
}: {
  busy: boolean;
  onSubmit: (files: File[], url: string) => void;
}) {
  const [files, setFiles] = useState<File[]>([]);
  const [url, setUrl] = useState('');
  const tooMany = files.length > MAX_FILES;
  const tooBig = files.reduce((sum, f) => sum + f.size, 0) > MAX_TOTAL_BYTES;
  const ready = (files.length > 0 && !tooMany && !tooBig) || url.trim() !== '';

  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (ready && !busy) onSubmit(files, url.trim());
  };

  return (
    <form onSubmit={submit} className="mt-bw-6 space-y-bw-4">
      <label className="block rounded-bw-lg border-2 border-dashed border-zinc-300 p-bw-6 text-center hover:border-bite">
        <span className="block text-bw-lg font-bold">Take or choose photos of the menu</span>
        <span className="mt-bw-1 block text-bw-sm text-zinc-500">
          {tooMany
            ? `That's ${files.length} files — up to ${MAX_FILES} per scan. Send the rest in a second scan.`
            : tooBig
              ? 'Those files are too big to scan together. Send them in smaller batches.'
              : files.length > 0
                ? `${files.length} file${files.length === 1 ? '' : 's'} ready`
                : 'One photo per page. PDFs work too.'}
        </span>
        <input
          type="file"
          accept="image/*,application/pdf"
          multiple
          capture="environment"
          aria-label="Menu photos"
          className="sr-only"
          onChange={(e) => {
            setFiles(Array.from(e.target.files ?? []));
            setUrl('');
          }}
        />
      </label>

      <p className="text-center text-bw-sm text-zinc-500">or</p>

      <input
        type="url"
        value={url}
        placeholder="Link to the menu page or PDF"
        aria-label="Menu link"
        onChange={(e) => {
          setUrl(e.target.value);
          setFiles([]);
        }}
        className="w-full rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base"
      />

      <button
        type="submit"
        disabled={!ready || busy}
        className="w-full rounded-bw-md bg-bite px-bw-6 py-bw-3 text-bw-base font-bold text-white hover:bg-bite-dark disabled:opacity-50"
      >
        {busy ? 'Sending…' : 'Scan the menu'}
      </button>
    </form>
  );
}

function Progress({
  scanId,
  startedAt,
  slug,
  onReady,
  onFail,
  onLost,
  onError,
}: {
  scanId: string;
  startedAt: number;
  slug: string;
  onReady: (dishes: ScanDish[], enrichmentFailed: boolean) => void;
  onFail: (message: string) => void;
  onLost: (message: string) => void;
  onError: (e: unknown) => void;
}) {
  const [seconds, setSeconds] = useState(0);
  const [checking, setChecking] = useState(false);
  // Latest callbacks without restarting the poll loop on every render.
  const handlers = useRef({ onReady, onFail, onLost, onError });
  handlers.current = { onReady, onFail, onLost, onError };

  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    let stopped = false;
    let misses = 0;
    let ready = false;

    const poll = async () => {
      try {
        const scan = await getScan(scanId);
        if (stopped) return;
        misses = 0;
        // A scan id from the URL can name any of this person's scans —
        // including a draft restaurant's, which the public lookup can't see.
        if (scan.restaurant_slug !== slug && scan.restaurant_id !== slug) {
          handlers.current.onFail('That scan is for a different restaurant.');
          return;
        }
        if (scan.failed) {
          handlers.current.onFail(
            "We couldn't read that menu. Try a sharper photo, or one page at a time.",
          );
          return;
        }
        // Dishes are reviewable before the background pass has added the
        // ingredients a name implies (a pizza's crust). That pass only
        // touches dishes still pending, so accepting early would publish
        // them without it — wait for it to finish.
        if (scan.ready && scan.enrichment_status !== 'pending') {
          handlers.current.onReady(scan.dishes ?? [], scan.enrichment_status === 'failed');
          return;
        }
        ready = scan.ready;
        if (scan.ready) setChecking(true);
      } catch (e) {
        if (stopped) return;
        if (e instanceof NotSignedInError) {
          handlers.current.onError(e);
          return;
        }
        // The scan keeps running server-side; a missed poll just means
        // asking again, not giving up on it.
        misses += 1;
        if (misses >= MAX_POLL_MISSES) {
          handlers.current.onLost(
            "We lost touch with the scan. It's still running — check your connection and keep waiting.",
          );
          return;
        }
      }
      if (Date.now() - startedAt > (ready ? ENRICHMENT_GIVE_UP_MS : GIVE_UP_MS)) {
        handlers.current.onLost('This scan is taking longer than it should.');
        return;
      }
      timer = setTimeout(poll, POLL_MS * 2 ** misses);
    };
    void poll();

    const tick = setInterval(() => setSeconds(Math.round((Date.now() - startedAt) / 1000)), 1000);
    return () => {
      stopped = true;
      if (timer) clearTimeout(timer);
      clearInterval(tick);
    };
  }, [scanId, startedAt, slug]);

  return (
    <div className="mt-bw-6 rounded-bw-lg bg-bite-light p-bw-6 text-center" aria-live="polite">
      <p className="text-bw-lg font-bold text-bite-dark">
        {checking ? 'Checking ingredients…' : 'Reading the menu…'}
      </p>
      <p className="mt-bw-1 text-bw-sm text-zinc-600">
        {checking
          ? 'Filling in what each dish implies, so the allergy filter can see it.'
          : 'Usually 20–60 seconds.'}{' '}
        {seconds > 0 && `${seconds}s so far.`}
      </p>
    </div>
  );
}

type Decisions = { accept: string[]; reject: string[] };

/**
 * Two groups, because "unticked" means two different things. In the main
 * list it means "not on the menu" and is recorded as rejected. In "Needs a
 * look" — dishes the filter can't vouch for, or that would rewrite a live
 * dish — unticked means "not yet": they stay pending for a fix in chat,
 * never thrown away for being flagged.
 */
function Review({
  dishes,
  enrichmentFailed,
  busy,
  onSubmit,
  onScanAnother,
}: {
  dishes: ScanDish[];
  enrichmentFailed: boolean;
  busy: boolean;
  onSubmit: (decisions: Decisions) => void;
  onScanAnother: () => void;
}) {
  const pending = useMemo(() => dishes.filter((d) => d.decision === 'pending'), [dishes]);
  // The filter can only hide what it can match: unmatched text or an empty
  // ingredient list would read as safe to everyone. If the ingredient pass
  // failed, nothing has been checked, so everything needs a look.
  // Unmatched or missing ingredients can't be published from here at all —
  // they wait for a fix in chat. A fully matched edit to a live dish can be,
  // as an explicit opt-in.
  const unsafe = (d: ScanDish) => enrichmentFailed || d.needs_attention;
  const [regular, flagged] = useMemo(() => {
    const needsLook = (d: ScanDish) => enrichmentFailed || d.needs_attention || editsLiveDish(d);
    return [pending.filter((d) => !needsLook(d)), pending.filter(needsLook)];
  }, [pending, enrichmentFailed]);
  const [picked, setPicked] = useState<Set<string>>(() => new Set(regular.map((d) => d.id)));

  const sections = useMemo(() => {
    const out = new Map<string, ScanDish[]>();
    for (const dish of regular) {
      const key = dish.section ?? 'Other';
      out.set(key, [...(out.get(key) ?? []), dish]);
    }
    return [...out.entries()];
  }, [regular]);

  if (pending.length === 0) {
    return (
      <div className="mt-bw-6">
        <p className="text-bw-base text-zinc-600">
          Nothing left to review on this scan. Try a clearer photo or a different page.
        </p>
        <button
          type="button"
          onClick={onScanAnother}
          className="mt-bw-3 rounded-bw-md bg-bite px-bw-6 py-bw-2 text-bw-base font-bold text-white hover:bg-bite-dark"
        >
          Scan another page
        </button>
      </div>
    );
  }

  const toggle = (id: string) =>
    setPicked((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const accept = pending.filter((d) => picked.has(d.id) && !unsafe(d)).map((d) => d.id);
  const reject = regular.filter((d) => !picked.has(d.id)).map((d) => d.id);
  const row = (dish: ScanDish) => (
    <DishRow
      key={dish.id}
      dish={dish}
      checked={picked.has(dish.id) && !unsafe(dish)}
      locked={unsafe(dish)}
      onToggle={() => toggle(dish.id)}
    />
  );

  let label = `Add ${accept.length} dish${accept.length === 1 ? '' : 'es'} to the menu`;
  if (accept.length === 0 && reject.length > 0)
    label = `Discard ${reject.length} dish${reject.length === 1 ? '' : 'es'}`;

  return (
    <div className="mt-bw-6">
      <p className="text-bw-base text-zinc-700">
        Found <span className="font-bold">{pending.length}</span> dishes.
        {regular.length > 0 &&
          ' Untick anything that isn\u2019t on the menu and it will be discarded.'}
        {enrichmentFailed && (
          <>
            {' '}
            <span className="font-semibold text-warn">
              We couldn&apos;t finish checking ingredients
            </span>
            , so every dish needs a look.
          </>
        )}
      </p>

      {sections.map(([section, sectionDishes]) => (
        <section key={section} className="mt-bw-6">
          <h2 className="text-bw-lg font-bold">{section}</h2>
          <ul className="mt-bw-2 divide-y divide-zinc-100">{sectionDishes.map(row)}</ul>
        </section>
      ))}

      {flagged.length > 0 && (
        <section className="mt-bw-6 rounded-bw-lg border border-warn/40 bg-warn/10 p-bw-3">
          <h2 className="text-bw-lg font-bold">Needs a look ({flagged.length})</h2>
          <p className="mt-bw-1 text-bw-sm text-zinc-700">
            Dishes whose ingredients we couldn&apos;t match can&apos;t be added from here — allergy
            filtering could miss something. They stay saved; fix them in chat. Tick an update to
            apply it to the dish already on the menu.
          </p>
          <ul className="mt-bw-2 divide-y divide-zinc-100">{flagged.map(row)}</ul>
        </section>
      )}

      <div className="sticky bottom-0 mt-bw-6 bg-white py-bw-3">
        <button
          type="button"
          disabled={busy || (accept.length === 0 && reject.length === 0)}
          onClick={() => onSubmit({ accept, reject })}
          className="w-full rounded-bw-md bg-bite px-bw-6 py-bw-3 text-bw-base font-bold text-white hover:bg-bite-dark disabled:opacity-50"
        >
          {busy ? 'Saving…' : label}
        </button>
      </div>
    </div>
  );
}

function DishRow({
  dish,
  checked,
  locked,
  onToggle,
}: {
  dish: ScanDish;
  checked: boolean;
  locked: boolean;
  onToggle: () => void;
}) {
  return (
    <li className="py-bw-3">
      <label className="flex cursor-pointer gap-bw-3">
        <input
          type="checkbox"
          checked={checked}
          disabled={locked}
          onChange={onToggle}
          aria-label={dish.name}
          className="mt-bw-1 h-4 w-4 accent-bite"
        />
        <span className="flex-1">
          <span className="flex items-baseline justify-between gap-bw-2">
            <span className="font-semibold">{dish.name}</span>
            {dish.prices.length > 0 && (
              <span className="text-bw-sm text-zinc-600">{formatPrices(dish.prices)}</span>
            )}
          </span>
          {dish.ingredients.length > 0 && (
            <span className="mt-bw-1 block text-bw-sm text-zinc-600">
              {dish.ingredients.join(', ')}
            </span>
          )}
          {dish.needs_attention && (
            <span className="mt-bw-1 block text-bw-sm font-semibold text-warn">
              {dish.unresolved.ingredients.length + dish.unresolved.tags.length > 0
                ? `Couldn't match: ${[...dish.unresolved.ingredients, ...dish.unresolved.tags].join(', ')}`
                : 'No ingredients found'}
            </span>
          )}
          {editsLiveDish(dish) && <LiveDishChanges dish={dish} />}
        </span>
      </label>
    </li>
  );
}

// Accepting a matched dish rewrites the live one, so it is opt-in and
// shows exactly what it would change.
function editsLiveDish(dish: ScanDish): boolean {
  return Boolean(dish.updates_existing_item && !dish.updates_existing_item.no_changes);
}

function LiveDishChanges({ dish }: { dish: ScanDish }) {
  const existing = dish.updates_existing_item;
  if (!existing) return null;
  const diff = existing.diff;
  return (
    <span className="mt-bw-1 block text-bw-sm text-bite-dark">
      Updates “{existing.name}”, already on the menu:
      <span className="block pl-bw-3">
        {diff.description && (
          <span className="block">
            Description: “{diff.description.from ?? ''}” → “{diff.description.to ?? ''}”
          </span>
        )}
        {diff.prices && (
          <span className="block">
            Price: {formatPrices(diff.prices.from)} → {formatPrices(diff.prices.to)}
          </span>
        )}
        {(diff.added_ingredients?.length ?? 0) > 0 && (
          <span className="block">Adds ingredients: {diff.added_ingredients?.join(', ')}</span>
        )}
        {(diff.added_tags?.length ?? 0) > 0 && (
          <span className="block">Adds tags: {diff.added_tags?.join(', ')}</span>
        )}
      </span>
    </span>
  );
}

// Every size with its price — accepting replaces all of a live dish's
// variants, so a size-only change has to be visible too.
function formatPrices(rows: { size?: string | null; price_cents: number }[] | undefined): string {
  const out = (rows ?? []).map((r) => {
    const money = `$${(r.price_cents / 100).toFixed(2)}`;
    return r.size ? `${r.size} ${money}` : money;
  });
  return out.join(' / ') || 'none';
}

// One at a time: every upload spends the same shared API budget as the
// polling, and a phone on a table's wifi does no better in parallel.
async function uploadInOrder(files: File[]): Promise<string[]> {
  const ids: string[] = [];
  for (const file of files) ids.push((await uploadAttachment(file)).id);
  return ids;
}
