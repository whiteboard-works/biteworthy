'use client';

import { useEffect, useState, type ReactElement } from 'react';
import { groupItemsBySection, type ItemSection } from '@biteworthy/filter-engine';
import type { ChatPane } from '../../lib/chat';
import {
  fetchRestaurantItemsClient,
  type RestaurantItem,
  type RestaurantItemsResponse,
} from '../../lib/restaurants';
import { getScan, type ScanDish, type ScanStatus } from '../../lib/scans';
import { HiddenReasonChip } from '../restaurants/[slug]/SectionList';

/**
 * What the assistant is acting on, drawn beside the transcript.
 *
 * The server sends a reference (`pane`) — which menu, which scan — and
 * this fetches the detail from the same REST endpoints the restaurant and
 * scan pages read, so the pane shows the site's own rendering of the
 * thing rather than the model-facing payload, which is fenced, trimmed
 * for tokens, and dropped by compaction. Read-only for now: the pane
 * shows, the composer acts.
 */

/** What was fetched, and for which reference — a view is drawn only under
 *  the pane it belongs to. */
type Loaded =
  | { key: string; revision: number; kind: 'menu'; data: RestaurantItemsResponse }
  | { key: string; revision: number; kind: 'scan'; data: ScanStatus };

/** How often to look again at a scan that is still extracting. The loop
 *  polls too, and each of its polls re-points the pane, but a person
 *  watching should not have to wait for the model's next round. */
const SCAN_POLL_MS = 4000;

export function ResultsPane({
  pane,
  revision = 0,
  working,
  onClose,
}: {
  pane: ChatPane | null;
  /** Bumped for every live `pane` event. An accept on a scan that was
   *  already staged points at the same reference as the listing before
   *  it, and the dishes' decisions have changed underneath — the value
   *  alone cannot say "look again", so the event does. */
  revision?: number;
  /** The running tool's own sentence, while one runs. */
  working: string | null;
  /** Phone width only — back to the transcript. */
  onClose?: () => void;
}): ReactElement {
  const [fetched, setFetched] = useState<Loaded | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Same reference, same revision, same fetch — the end-of-turn refetch
  // hands back the pane the live event already drew, and must not redraw it.
  const key = pane ? paneKey(pane) : null;
  // Re-pointed to menu B, the pane must not keep drawing menu A under B's
  // title — with B's slug in every link — while B loads. Nor may the menu
  // from before an avoid-list change stay up while the same reference is
  // fetched again: its "you can eat" labels are the ones the change just
  // made wrong. Until the current fetch lands the pane shows what the
  // tool reported and nothing else.
  const loaded = fetched && fetched.key === key && fetched.revision === revision ? fetched : null;

  useEffect(() => {
    if (!pane || !key) {
      // A fetch cancelled by the switch never gets to clear these itself.
      setError(null);
      setLoading(false);
      return undefined;
    }
    let live = true;
    let timer: ReturnType<typeof setTimeout> | undefined;
    // Whether the last answer said "still extracting". One failed poll —
    // a dropped connection, a proxy 502 — must not end the watch, so a
    // failure while polling asks again on the same cadence.
    let polling = false;
    const again = () => {
      timer = setTimeout(() => void load(), SCAN_POLL_MS);
    };
    const load = async () => {
      setLoading(true);
      try {
        const next = await fetchFor(pane, key, revision);
        if (!live) return;
        setError(null);
        // An unknown kind from a newer server is not an error, just
        // nothing this build can show.
        if (next) setFetched(next);
        polling = next?.kind === 'scan' && !next.data.ready && !next.data.failed;
        if (polling) again();
      } catch (e) {
        if (!live) return;
        setError((e as Error).message);
        if (polling) again();
      } finally {
        if (live) setLoading(false);
      }
    };
    void load();
    return () => {
      live = false;
      if (timer) clearTimeout(timer);
    };
    // `key` is the pane's identity; `pane` itself is a new object each render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, revision]);

  return (
    <div data-testid="results-pane" className="flex h-full min-h-0 flex-col">
      <header className="flex items-center justify-between gap-bw-2 border-b border-zinc-200 px-bw-4 py-bw-3">
        <h2 className="truncate text-bw-base font-bold text-zinc-900">{title(pane, loaded)}</h2>
        <div className="flex items-center gap-bw-2">
          {loading ? <span className="text-bw-xs text-zinc-400">Updating…</span> : null}
          {onClose ? (
            <button
              type="button"
              onClick={onClose}
              className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1 text-bw-sm text-zinc-700 lg:hidden"
            >
              Chat
            </button>
          ) : null}
        </div>
      </header>
      {working ? (
        <p
          data-testid="pane-working"
          className="border-b border-zinc-100 px-bw-4 py-bw-2 text-bw-sm text-zinc-500"
        >
          {working}…
        </p>
      ) : null}
      <div className="min-h-0 flex-1 overflow-y-auto px-bw-4 py-bw-4">
        {error ? (
          <p role="alert" className="text-bw-sm text-danger">
            {error}
          </p>
        ) : null}
        {!pane ? <Empty /> : null}
        {pane && !loaded && !error ? <Summary pane={pane} /> : null}
        {loaded?.kind === 'menu' ? <MenuView pane={pane} data={loaded.data} /> : null}
        {loaded?.kind === 'scan' ? <ScanView data={loaded.data} /> : null}
      </div>
    </div>
  );
}

/** The reference's identity. Built from sorted entries, not the object as
 *  it came: the stored copy has been through `jsonb`, which reorders
 *  keys, and it must read as the same pane the live event carried. */
function paneKey(pane: ChatPane): string {
  return JSON.stringify(
    Object.entries(pane)
      .filter(([, v]) => v !== null && v !== undefined)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)),
  );
}

async function fetchFor(pane: ChatPane, key: string, revision: number): Promise<Loaded | null> {
  if (pane.kind === 'menu' && pane.restaurant) {
    const data = await fetchRestaurantItemsClient(pane.restaurant, {
      signedIn: true,
      presetSlug: pane.preset ?? undefined,
      strictness: pane.strictness ?? undefined,
    });
    return { key, revision, kind: 'menu', data };
  }
  if (pane.kind === 'scan' && pane.scan_id) {
    return { key, revision, kind: 'scan', data: await getScan(pane.scan_id) };
  }
  return null;
}

function title(pane: ChatPane | null, loaded: Loaded | null): string {
  if (!pane) return 'Results';
  if (pane.kind === 'menu') return pane.restaurant ? `Menu · ${pane.restaurant}` : 'Menu';
  if (pane.kind === 'scan') {
    const slug = loaded?.kind === 'scan' ? loaded.data.restaurant_slug : pane.restaurant;
    return slug ? `Scan · ${slug}` : 'Scan';
  }
  return 'Results';
}

function Empty(): ReactElement {
  return (
    <p data-testid="pane-empty" className="text-bw-sm text-zinc-500">
      When the assistant reads a menu or scans one, it shows up here.
    </p>
  );
}

/** What the tool reported, shown until the detail arrives. */
function Summary({ pane }: { pane: ChatPane }): ReactElement | null {
  if (pane.kind === 'menu' && pane.visible_count != null) {
    return (
      <p className="text-bw-sm text-zinc-500">
        {pane.visible_count} you can eat · {pane.hidden_count ?? 0} hidden by your filter
      </p>
    );
  }
  if (pane.kind === 'scan') {
    return <p className="text-bw-sm text-zinc-500">{pane.status ?? 'Scanning'}…</p>;
  }
  return null;
}

function MenuView({
  pane,
  data,
}: {
  pane: ChatPane | null;
  data: RestaurantItemsResponse;
}): ReactElement {
  const sections = groupItemsBySection(data.items);
  const visible = data.items.filter((i) => i.status === 'visible').length;
  const hidden = data.items.length - visible;
  const slug = pane?.restaurant ?? '';
  const preset = data.filter.preset_slug;
  return (
    <div data-testid="pane-menu">
      <p className="text-bw-sm text-zinc-500">
        <span className="font-semibold text-zinc-700">{visible}</span> you can eat ·{' '}
        <span className="font-semibold text-zinc-700">{hidden}</span> hidden
        {preset ? ` · ${preset}` : ''} · {data.filter.strictness}
      </p>
      {sections.map((section) => (
        <MenuSection key={section.id ?? 'none'} section={section} slug={slug} preset={preset} />
      ))}
      {data.items.length === 0 ? (
        <p className="mt-bw-4 text-bw-sm text-zinc-500">No published dishes yet.</p>
      ) : null}
    </div>
  );
}

function MenuSection({
  section,
  slug,
  preset,
}: {
  section: ItemSection<RestaurantItem>;
  slug: string;
  preset: string | null;
}): ReactElement {
  const href = (item: RestaurantItem) =>
    `/restaurants/${encodeURIComponent(slug)}/items/${encodeURIComponent(item.id)}${
      preset ? `?profile=${encodeURIComponent(preset)}` : ''
    }`;
  const row = (item: RestaurantItem, hidden: boolean) => (
    <li key={item.id} data-testid={`pane-item-${item.id}`} className="py-bw-2">
      {/* A new tab: the pane sits beside a chat that may be mid-turn, and
          leaving the page would drop the stream, the queue, and the draft. */}
      <a
        href={href(item)}
        target="_blank"
        rel="noopener"
        className={`text-bw-sm font-semibold hover:underline ${
          hidden ? 'text-zinc-400' : 'text-zinc-900'
        }`}
      >
        {item.name}
      </a>
      {hidden && item.reasons.length > 0 ? (
        <span className="ml-bw-2 inline-flex flex-wrap gap-bw-1 align-middle">
          {item.reasons.map((reason, i) => (
            <HiddenReasonChip key={i} reason={reason} />
          ))}
        </span>
      ) : null}
    </li>
  );
  return (
    <section className="mt-bw-4">
      <h3 className="text-bw-sm font-bold uppercase tracking-wide text-zinc-500">{section.name}</h3>
      <ul className="divide-y divide-zinc-100">
        {section.visible.map((item) => row(item, false))}
        {section.hidden.map((item) => row(item, true))}
      </ul>
    </section>
  );
}

function ScanView({ data }: { data: ScanStatus }): ReactElement {
  if (data.failed) {
    return (
      <p data-testid="pane-scan" role="alert" className="text-bw-sm text-danger">
        {data.failure_message ?? 'The scan failed.'}
      </p>
    );
  }
  if (!data.ready) {
    return (
      <div data-testid="pane-scan">
        <p className="text-bw-sm text-zinc-700">Reading the menu — usually 20 to 60 seconds.</p>
        <p className="mt-bw-1 text-bw-xs text-zinc-400">{data.status}</p>
      </div>
    );
  }
  const dishes = data.dishes ?? [];
  const groups = new Map<string, ScanDish[]>();
  for (const dish of dishes) {
    const name = dish.section ?? 'Other';
    groups.set(name, [...(groups.get(name) ?? []), dish]);
  }
  return (
    <div data-testid="pane-scan">
      <p className="text-bw-sm text-zinc-500">
        <span className="font-semibold text-zinc-700">{data.dish_count}</span> found ·{' '}
        {data.pending_count} to review · {data.accepted_count} on the menu
        {data.rejected_count > 0 ? ` · ${data.rejected_count} discarded` : ''}
      </p>
      {[...groups.entries()].map(([section, rows]) => (
        <section key={section} className="mt-bw-4">
          <h3 className="text-bw-sm font-bold uppercase tracking-wide text-zinc-500">{section}</h3>
          <ul className="divide-y divide-zinc-100">
            {rows.map((dish) => (
              <li key={dish.id} data-testid={`pane-dish-${dish.id}`} className="py-bw-2">
                <span className="flex items-baseline justify-between gap-bw-2">
                  <span
                    className={`text-bw-sm font-semibold ${
                      dish.decision === 'rejected' ? 'text-zinc-400 line-through' : 'text-zinc-900'
                    }`}
                  >
                    {dish.name}
                  </span>
                  <Decision dish={dish} />
                </span>
                {dish.ingredients.length > 0 ? (
                  <span className="mt-bw-0_5 block text-bw-xs text-zinc-500">
                    {dish.ingredients.join(', ')}
                  </span>
                ) : null}
                {dish.needs_attention ? (
                  <span className="mt-bw-0_5 block text-bw-xs font-semibold text-warn">
                    Needs a look
                  </span>
                ) : null}
              </li>
            ))}
          </ul>
        </section>
      ))}
    </div>
  );
}

function Decision({ dish }: { dish: ScanDish }): ReactElement | null {
  if (dish.decision === 'pending') return null;
  const label =
    dish.decision === 'accepted'
      ? 'On the menu'
      : dish.decision === 'rejected'
        ? 'Discarded'
        : 'Edited';
  return <span className="shrink-0 text-bw-xs text-zinc-400">{label}</span>;
}
