'use client';

import { useEffect, useRef, useState } from 'react';
import { searchIngredients, fetchTags, type TasteTag } from '../../../../lib/onboarding';
import type { IngestionItemEdits, IngestionItemPayload } from '../../../../lib/ingestion';

/**
 * Correct a staged dish before it goes live. Everything the extractor
 * can get wrong is editable here — name, description, the
 * ingredient/tag chips that drive the allergen filter, and the prices
 * that become ItemVariants — because fixing the staged row is strictly
 * better than fixing the live menu afterwards.
 *
 * Chips are stored as slugs; the pickers search the public taxonomy
 * endpoints (ingredients by `q`, tags fetched once and filtered
 * locally — there are only a couple hundred).
 *
 * On a matched (re-scan) card the server applies updates append-only,
 * so removing a chip here only keeps it out of what gets added — the
 * live item keeps it. The panel says so rather than implying otherwise.
 */

export interface EditDraft {
  name: string;
  description: string;
  ingredientSlugs: string[];
  tagSlugs: string[];
  prices: Array<{ size: string; price: string }>;
}

export function draftFromItem(item: IngestionItemPayload): EditDraft {
  return {
    name: item.name ?? '',
    description: item.description ?? '',
    ingredientSlugs: item.ingredients_payload.map((row) => row.slug),
    tagSlugs: item.tags_payload.map((row) => row.slug),
    prices: item.prices_payload.map((row) => ({
      size: row.size ?? '',
      // Cents → editable dollars; blank stays blank so a priceless row
      // round-trips instead of becoming $0.00.
      price: row.price_cents == null ? '' : (row.price_cents / 100).toFixed(2),
    })),
  };
}

/** Draft → the PATCH body's edit fields. Rows without a parsable price are dropped. */
export function editsFromDraft(draft: EditDraft): IngestionItemEdits {
  return {
    name: draft.name.trim(),
    description: draft.description.trim(),
    ingredients_payload: draft.ingredientSlugs.map((slug) => ({ slug })),
    tags_payload: draft.tagSlugs.map((slug) => ({ slug })),
    prices_payload: draft.prices.flatMap((row) => {
      const cents = Math.round(Number.parseFloat(row.price) * 100);
      if (!Number.isFinite(cents)) return [];
      return [{ size: row.size.trim() || null, price_cents: cents }];
    }),
  };
}

interface Option {
  slug: string;
  name: string;
}

export function ItemEditPanel({
  draft,
  onChange,
  matched,
}: {
  draft: EditDraft;
  onChange: (next: EditDraft) => void;
  /** Re-scan card: updates are append-only server-side. */
  matched?: boolean;
}) {
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
        <p className="rounded bg-amber-50 px-2 py-1 text-xs text-amber-800" data-testid="edit-append-note">
          This dish is already on the menu. Edits here shape what gets <strong>added</strong> —
          removing a chip won&rsquo;t take it off the live dish (do that from the restaurant admin).
        </p>
      )}

      <ChipEditor
        label="Ingredients"
        testId="ingredients"
        slugs={draft.ingredientSlugs}
        onChange={(ingredientSlugs) => onChange({ ...draft, ingredientSlugs })}
        search={async (q) => {
          const rows = await searchIngredients(q);
          return rows.map((r) => ({ slug: r.slug, name: r.name }));
        }}
      />

      <ChipEditor
        label="Tags"
        testId="tags"
        slugs={draft.tagSlugs}
        onChange={(tagSlugs) => onChange({ ...draft, tagSlugs })}
        search={async (q) => {
          // The tag catalog is small (a couple hundred), so one fetch
          // + local filtering beats a search endpoint that doesn't exist.
          const rows = await fetchTags([]);
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

      <PriceEditor prices={draft.prices} onChange={(prices) => onChange({ ...draft, prices })} />
    </div>
  );
}

function ChipEditor({
  label,
  testId,
  slugs,
  onChange,
  search,
}: {
  label: string;
  testId: string;
  slugs: string[];
  onChange: (next: string[]) => void;
  search: (q: string) => Promise<Option[]>;
}) {
  const [query, setQuery] = useState('');
  const [options, setOptions] = useState<Option[]>([]);
  const [searching, setSearching] = useState(false);
  const seq = useRef(0);

  useEffect(() => {
    if (query.trim().length < 2) {
      setOptions([]);
      return;
    }
    const mine = ++seq.current;
    setSearching(true);
    search(query)
      .then((rows) => {
        // Ignore a slower earlier response landing after a newer one.
        if (mine === seq.current) setOptions(rows.filter((r) => !slugs.includes(r.slug)));
      })
      .catch(() => {
        if (mine === seq.current) setOptions([]);
      })
      .finally(() => {
        if (mine === seq.current) setSearching(false);
      });
    // `search` and `slugs` are re-created per render by the parent;
    // depending on them would refetch on every keystroke of an
    // unrelated field.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query]);

  const add = (slug: string) => {
    if (!slugs.includes(slug)) onChange([...slugs, slug]);
    setQuery('');
    setOptions([]);
  };

  return (
    <div className="text-sm" data-testid={`edit-${testId}`}>
      <span className="text-zinc-600">{label}</span>
      <p className="mt-1 flex flex-wrap gap-1">
        {slugs.map((slug) => (
          <span
            key={slug}
            className="inline-flex items-center gap-1 rounded-full bg-zinc-100 px-2 py-0.5 text-xs text-zinc-700"
          >
            {slug}
            <button
              type="button"
              onClick={() => onChange(slugs.filter((s) => s !== slug))}
              aria-label={`Remove ${slug}`}
              data-testid={`remove-${testId}-${slug}`}
              className="font-bold text-zinc-400 hover:text-red-700"
            >
              ×
            </button>
          </span>
        ))}
        {slugs.length === 0 && <span className="text-xs italic text-zinc-400">none</span>}
      </p>
      <input
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder={`Add ${label.toLowerCase()}…`}
        data-testid={`search-${testId}`}
        className="mt-1 w-full rounded border border-zinc-300 px-2 py-1 text-xs"
      />
      {searching && <p className="mt-1 text-xs text-zinc-400">searching…</p>}
      {options.length > 0 && (
        <ul className="mt-1 max-h-32 overflow-y-auto rounded border border-zinc-200">
          {options.map((option) => (
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

function PriceEditor({
  prices,
  onChange,
}: {
  prices: EditDraft['prices'];
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
              data-testid={`price-amount-${index}`}
              className="w-24 rounded border border-zinc-300 px-2 py-1 text-xs"
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
