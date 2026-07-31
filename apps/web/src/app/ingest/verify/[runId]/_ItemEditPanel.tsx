'use client';

import { useEffect, useRef, useState } from 'react';
import { searchIngredients, fetchTags, type TasteTag } from '../../../../lib/onboarding';
import type { IngestionItemEdits, IngestionItemPayload } from '../../../../lib/ingestion';

/**
 * Correct a staged dish before it goes live. Everything the extractor
 * can get wrong is editable — name, description, the ingredient/tag
 * chips that drive the allergen filter, and the prices that become
 * ItemVariants — because fixing the staged row is strictly better than
 * fixing the live menu afterwards.
 *
 * Two rules keep an edit from destroying data it never meant to touch:
 *
 *   1. Only CHANGED facets are sent. Payload arrays replace wholesale
 *      server-side, and the background gap-fill pass keeps appending
 *      chips while this panel is open — resending an untouched array
 *      would silently wipe an allergen it just added.
 *   2. Chip rows keep their original `confidence`/`source`. Those drive
 *      strict-mode trust and tell gap-fill which rows are machine-owned;
 *      rebuilding rows as bare `{slug}` would erase that provenance.
 *      Rows a human adds are marked source: "human", confidence: 1 —
 *      a person asserting an ingredient is the strongest signal there is.
 *
 * On a matched (re-scan) card the server applies updates append-only,
 * so removing a chip here only keeps it out of what gets added — the
 * live item keeps it. The panel says so rather than implying otherwise.
 */

export interface PayloadRow {
  slug: string;
  confidence?: number;
  source?: string;
}

export interface EditDraft {
  name: string;
  description: string;
  ingredients: PayloadRow[];
  tags: PayloadRow[];
  prices: Array<{ size: string; price: string }>;
  /** `source` is carried, not edited — it records who first saw the add-on. */
  addons: Array<{ name: string; price: string; source?: 'extract' | 'guard' }>;
}

/** Cents → the dollars string shown in the input ('' for a priceless row). */
function centsToInput(cents: number | null | undefined): string {
  return cents == null ? '' : (cents / 100).toFixed(2);
}

export function draftFromItem(item: IngestionItemPayload): EditDraft {
  return {
    name: item.name ?? '',
    description: item.description ?? '',
    ingredients: item.ingredients_payload.map((row) => ({ ...row })),
    tags: item.tags_payload.map((row) => ({ ...row })),
    prices: item.prices_payload.map((row) => ({
      size: row.size ?? '',
      price: centsToInput(row.price_cents),
    })),
    addons: (item.addons_payload ?? []).map((row) => ({
      name: row.name ?? '',
      price: centsToInput(row.price_cents),
      source: row.source,
    })),
  };
}

/** A price the user typed: dollars with at most two decimals, no sign. */
const PRICE_INPUT = /^\d+(\.\d{1,2})?$/;

export function priceRowErrors(draft: EditDraft): number[] {
  return draft.prices.flatMap((row, index) =>
    row.price.trim() !== '' && !PRICE_INPUT.test(row.price.trim()) ? [index] : [],
  );
}

export function addonRowErrors(draft: EditDraft): number[] {
  return draft.addons.flatMap((row, index) =>
    row.price.trim() !== '' && !PRICE_INPUT.test(row.price.trim()) ? [index] : [],
  );
}

/** Rows that would lose their price at promote, for the name input's error state. */
export function addonNameErrors(draft: EditDraft): number[] {
  return draft.addons.flatMap((row, index) =>
    row.name.trim() === '' && row.price.trim() !== '' ? [index] : [],
  );
}

/**
 * Blocks Save/Accept: a nameless dish 422s at promote, junk prices
 * mislead. `matched` suppresses the add-on checks — a matched card
 * can't edit add-ons at all (see the panel), so blocking on one the
 * extractor produced would strand a card the verifier never touched.
 */
export function draftBlockers(draft: EditDraft, matched = false): string | null {
  if (draft.name.trim() === '') return 'Give the dish a name before saving.';
  if (priceRowErrors(draft).length > 0) return 'Prices must look like 8 or 8.95.';
  if (matched) return null;

  if (addonRowErrors(draft).length > 0) return 'Prices must look like 8 or 8.95.';
  // Promote drops a nameless add-on, so saving one would quietly lose
  // the price typed against it.
  if (addonNameErrors(draft).length > 0) return 'Give every add-on a name.';
  return null;
}

function pricesToPayload(draft: EditDraft) {
  return draft.prices.flatMap((row) => {
    const trimmed = row.price.trim();
    if (!PRICE_INPUT.test(trimmed)) return [];
    return [{ size: row.size.trim() || null, price_cents: Math.round(Number(trimmed) * 100) }];
  });
}

function addonsToPayload(draft: EditDraft) {
  return draft.addons.flatMap((row) => {
    const name = row.name.trim();
    const price = row.price.trim();
    // Neither = a row added and never filled in. A named add-on with no
    // price is real (plenty are free), and travels with a null price.
    if (name === '' && price === '') return [];
    return [
      {
        name,
        price_cents: PRICE_INPUT.test(price) ? Math.round(Number(price) * 100) : null,
        ...(row.source ? { source: row.source } : {}),
      },
    ];
  });
}

function sameRows(a: PayloadRow[], b: PayloadRow[]): boolean {
  return a.length === b.length && a.every((row, i) => row.slug === b[i]?.slug);
}

/**
 * Draft → PATCH edit fields, comparing against the draft the panel was
 * seeded with so untouched facets are omitted entirely (see rule 1).
 */
export function editsFromDraft(draft: EditDraft, baseline: EditDraft): IngestionItemEdits {
  const edits: IngestionItemEdits = {};
  if (draft.name.trim() !== baseline.name.trim()) edits.name = draft.name.trim();
  if (draft.description.trim() !== baseline.description.trim()) {
    edits.description = draft.description.trim();
  }
  if (!sameRows(draft.ingredients, baseline.ingredients)) {
    edits.ingredients_payload = draft.ingredients;
  }
  if (!sameRows(draft.tags, baseline.tags)) edits.tags_payload = draft.tags;

  const prices = pricesToPayload(draft);
  const basePrices = pricesToPayload(baseline);
  if (JSON.stringify(prices) !== JSON.stringify(basePrices)) edits.prices_payload = prices;

  const addons = addonsToPayload(draft);
  if (JSON.stringify(addons) !== JSON.stringify(addonsToPayload(baseline))) {
    edits.addons_payload = addons;
  }

  return edits;
}

interface Option {
  slug: string;
  name: string;
}

export function ItemEditPanel({
  draft,
  onChange,
  matched,
  onCancel,
}: {
  draft: EditDraft;
  onChange: (next: EditDraft) => void;
  /** Re-scan card: updates are append-only server-side. */
  matched?: boolean;
  onCancel: () => void;
}) {
  const blocker = draftBlockers(draft);
  const badPrices = new Set(priceRowErrors(draft));
  const badAddons = new Set(addonRowErrors(draft));
  const missingAddonNames = new Set(addonNameErrors(draft));

  return (
    <div className="mt-3 space-y-3 border-t border-zinc-200 pt-3" data-testid="item-edit-panel">
      <label className="block text-sm">
        <span className="text-zinc-600">Name</span>
        <input
          value={draft.name}
          onChange={(e) => onChange({ ...draft, name: e.target.value })}
          data-testid="edit-name"
          className="mt-1 w-full rounded border border-zinc-300 px-2 py-1"
        />
      </label>

      <label className="block text-sm">
        <span className="text-zinc-600">Description</span>
        <textarea
          value={draft.description}
          onChange={(e) => onChange({ ...draft, description: e.target.value })}
          data-testid="edit-description"
          rows={2}
          className="mt-1 w-full rounded border border-zinc-300 px-2 py-1"
        />
      </label>

      {matched && (
        <p
          className="rounded bg-amber-50 px-2 py-1 text-xs text-amber-800"
          data-testid="edit-append-note"
        >
          This dish is already on the menu. Edits here shape what gets <strong>added</strong> —
          removing a chip won&rsquo;t take it off the live dish, and the name and add-ons
          aren&rsquo;t applied at all. Change those from the restaurant admin.
        </p>
      )}

      <ChipEditor
        label="Ingredients"
        testId="ingredients"
        rows={draft.ingredients}
        onChange={(ingredients) => onChange({ ...draft, ingredients })}
        search={async (q) => {
          const rows = await searchIngredients(q);
          return rows.map((r) => ({ slug: r.slug, name: r.name }));
        }}
      />

      <ChipEditor
        label="Tags"
        testId="tags"
        rows={draft.tags}
        onChange={(tags) => onChange({ ...draft, tags })}
        search={async (q) => {
          const rows = await loadTagCatalog();
          const needle = q.trim().toLowerCase();
          return rows
            .filter(
              (r: TasteTag) =>
                r.name.toLowerCase().includes(needle) || r.slug.toLowerCase().includes(needle),
            )
            .slice(0, 20)
            .map((r: TasteTag) => ({ slug: r.slug, name: r.name }));
        }}
      />

      <PriceEditor
        prices={draft.prices}
        invalid={badPrices}
        onChange={(prices) => onChange({ ...draft, prices })}
      />

      {/* A matched card promotes through apply_update!, which leaves
          modifiers alone by design — so an add-on editor here would
          accept corrections and silently do nothing with them. */}
      {!matched && (
        <AddonEditor
          addons={draft.addons}
          invalid={badAddons}
          namesMissing={missingAddonNames}
          onChange={(addons) => onChange({ ...draft, addons })}
        />
      )}

      <div className="flex items-center justify-between">
        {blocker ? (
          <p role="alert" data-testid="edit-blocker" className="text-xs text-red-700">
            {blocker}
          </p>
        ) : (
          <span />
        )}
        <button
          type="button"
          onClick={onCancel}
          data-testid="cancel-edit"
          className="text-xs font-semibold text-zinc-500 underline hover:text-zinc-800"
        >
          Discard changes
        </button>
      </div>
    </div>
  );
}

/**
 * The tag catalog has no search endpoint and is small, so it's fetched
 * once per page rather than per keystroke.
 */
let tagCatalog: Promise<TasteTag[]> | null = null;
function loadTagCatalog(): Promise<TasteTag[]> {
  tagCatalog ??= fetchTags([]).catch((e: unknown) => {
    tagCatalog = null; // let the next keystroke retry
    throw e;
  });
  return tagCatalog;
}

const SEARCH_DEBOUNCE_MS = 250;

function ChipEditor({
  label,
  testId,
  rows,
  onChange,
  search,
}: {
  label: string;
  testId: string;
  rows: PayloadRow[];
  onChange: (next: PayloadRow[]) => void;
  search: (q: string) => Promise<Option[]>;
}) {
  const [query, setQuery] = useState('');
  const [options, setOptions] = useState<Option[]>([]);
  const [searching, setSearching] = useState(false);
  const seq = useRef(0);

  useEffect(() => {
    // Bumping the sequence on EVERY change invalidates in-flight
    // responses for abandoned queries, including when the user
    // backspaces below the threshold.
    const mine = ++seq.current;
    if (query.trim().length < 2) {
      setOptions([]);
      setSearching(false);
      return;
    }
    setSearching(true);
    const timer = setTimeout(() => {
      search(query)
        .then((found) => {
          if (mine === seq.current) setOptions(found);
        })
        .catch(() => {
          if (mine === seq.current) setOptions([]);
        })
        .finally(() => {
          if (mine === seq.current) setSearching(false);
        });
    }, SEARCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
    // `search` is re-created by the parent on every render; depending on
    // it would refetch on unrelated keystrokes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query]);

  const slugs = rows.map((row) => row.slug);
  // Filtered at render, not at fetch — a chip removed while the
  // dropdown is open must become addable again immediately.
  const suggestions = options.filter((option) => !slugs.includes(option.slug));

  const add = (slug: string) => {
    if (!slugs.includes(slug)) {
      // A human asserting an ingredient is the strongest signal we have.
      onChange([...rows, { slug, confidence: 1, source: 'human' }]);
    }
    setQuery('');
    setOptions([]);
  };

  return (
    <div className="text-sm" data-testid={`edit-${testId}`}>
      <span className="text-zinc-600">{label}</span>
      <p className="mt-1 flex flex-wrap gap-1">
        {rows.map((row) => (
          <span
            key={row.slug}
            className="inline-flex items-center gap-1 rounded-full bg-zinc-100 px-2 py-0.5 text-xs text-zinc-700"
          >
            {row.slug}
            <button
              type="button"
              onClick={() => onChange(rows.filter((r) => r.slug !== row.slug))}
              aria-label={`Remove ${row.slug}`}
              data-testid={`remove-${testId}-${row.slug}`}
              className="font-bold text-zinc-400 hover:text-red-700"
            >
              ×
            </button>
          </span>
        ))}
        {rows.length === 0 && <span className="text-xs italic text-zinc-400">none</span>}
      </p>
      <input
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder={`Add ${label.toLowerCase()}…`}
        aria-label={`Search ${label.toLowerCase()} to add`}
        data-testid={`search-${testId}`}
        className="mt-1 w-full rounded border border-zinc-300 px-2 py-1 text-xs"
      />
      {searching && <p className="mt-1 text-xs text-zinc-400">searching…</p>}
      {suggestions.length > 0 && (
        <ul className="mt-1 max-h-32 overflow-y-auto rounded border border-zinc-200">
          {suggestions.map((option) => (
            <li key={option.slug}>
              <button
                type="button"
                onClick={() => add(option.slug)}
                data-testid={`add-${testId}-${option.slug}`}
                className="block w-full px-2 py-1 text-left text-xs hover:bg-zinc-50"
              >
                {option.name} <span className="text-zinc-400">{option.slug}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

/**
 * Add-ons become ItemModifiers at promote, all `kind: "addition"` —
 * the staged payload has no kind, so a choice/side distinction is made
 * afterwards in the restaurant admin. `source` rides along untouched so
 * a row the extractor found stays attributable.
 */
function AddonEditor({
  addons,
  invalid,
  namesMissing,
  onChange,
}: {
  addons: EditDraft['addons'];
  invalid: Set<number>;
  /** Rows blocking the save because a price has no name to hang on. */
  namesMissing: Set<number>;
  onChange: (next: EditDraft['addons']) => void;
}) {
  return (
    <div className="text-sm" data-testid="edit-addons">
      <span className="text-zinc-600">Add-ons</span>
      <ul className="mt-1 space-y-1">
        {addons.map((row, index) => (
          <li key={index} className="flex items-center gap-2">
            <input
              value={row.name}
              onChange={(e) =>
                onChange(addons.map((r, i) => (i === index ? { ...r, name: e.target.value } : r)))
              }
              placeholder="add-on name"
              aria-label={`Name for add-on ${index + 1}`}
              aria-invalid={namesMissing.has(index)}
              data-testid={`addon-name-${index}`}
              className={`w-1/2 rounded border px-2 py-1 text-xs ${
                namesMissing.has(index) ? 'border-red-400 bg-red-50' : 'border-zinc-300'
              }`}
            />
            <span className="text-xs text-zinc-400">$</span>
            <input
              value={row.price}
              onChange={(e) =>
                onChange(addons.map((r, i) => (i === index ? { ...r, price: e.target.value } : r)))
              }
              inputMode="decimal"
              placeholder="0.00"
              aria-label={`Price for add-on ${index + 1}`}
              aria-invalid={invalid.has(index)}
              data-testid={`addon-price-${index}`}
              className={`w-24 rounded border px-2 py-1 text-xs ${
                invalid.has(index) ? 'border-red-400 bg-red-50' : 'border-zinc-300'
              }`}
            />
            <button
              type="button"
              onClick={() => onChange(addons.filter((_, i) => i !== index))}
              aria-label={`Remove add-on ${index + 1}`}
              data-testid={`remove-addon-${index}`}
              className="text-xs font-bold text-zinc-400 hover:text-red-700"
            >
              ×
            </button>
          </li>
        ))}
      </ul>
      <button
        type="button"
        onClick={() => onChange([...addons, { name: '', price: '' }])}
        data-testid="add-addon"
        className="mt-1 text-xs font-semibold text-zinc-600 underline hover:text-zinc-900"
      >
        + Add an add-on
      </button>
    </div>
  );
}

function PriceEditor({
  prices,
  invalid,
  onChange,
}: {
  prices: EditDraft['prices'];
  invalid: Set<number>;
  onChange: (next: EditDraft['prices']) => void;
}) {
  return (
    <div className="text-sm" data-testid="edit-prices">
      <span className="text-zinc-600">Prices</span>
      <ul className="mt-1 space-y-1">
        {prices.map((row, index) => (
          <li key={index} className="flex items-center gap-2">
            <input
              value={row.size}
              onChange={(e) =>
                onChange(prices.map((r, i) => (i === index ? { ...r, size: e.target.value } : r)))
              }
              placeholder="size (optional)"
              aria-label={`Size for price row ${index + 1}`}
              data-testid={`price-size-${index}`}
              className="w-1/2 rounded border border-zinc-300 px-2 py-1 text-xs"
            />
            <span className="text-xs text-zinc-400">$</span>
            <input
              value={row.price}
              onChange={(e) =>
                onChange(prices.map((r, i) => (i === index ? { ...r, price: e.target.value } : r)))
              }
              inputMode="decimal"
              placeholder="0.00"
              aria-label={`Amount for price row ${index + 1}`}
              aria-invalid={invalid.has(index)}
              data-testid={`price-amount-${index}`}
              className={`w-24 rounded border px-2 py-1 text-xs ${
                invalid.has(index) ? 'border-red-400 bg-red-50' : 'border-zinc-300'
              }`}
            />
            <button
              type="button"
              onClick={() => onChange(prices.filter((_, i) => i !== index))}
              aria-label={`Remove price row ${index + 1}`}
              data-testid={`remove-price-${index}`}
              className="text-xs font-bold text-zinc-400 hover:text-red-700"
            >
              ×
            </button>
          </li>
        ))}
      </ul>
      <button
        type="button"
        onClick={() => onChange([...prices, { size: '', price: '' }])}
        data-testid="add-price"
        className="mt-1 text-xs font-semibold text-zinc-600 underline hover:text-zinc-900"
      >
        + Add a price
      </button>
    </div>
  );
}
