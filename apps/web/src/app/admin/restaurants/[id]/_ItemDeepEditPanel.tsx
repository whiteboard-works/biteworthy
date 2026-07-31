'use client';

import { useEffect, useRef, useState } from 'react';
import { searchIngredients, fetchTags, type TasteTag } from '../../../../lib/onboarding';
import type {
  AdminItemEdits,
  AdminItemRow,
  AdminModifierKind,
} from '../../../../lib/admin/management';

/**
 * Deep-edit a live dish: name, description, the ingredient/tag chips
 * that drive the allergen filter, prices, modifiers, and which section
 * it sits in. This is the counterpart to verify-flow editing — the
 * place to fix something that already reached the menu.
 *
 * Two rules mirror the server:
 *   - Only CHANGED facets are sent. Slug lists and the variant/modifier
 *     arrays replace wholesale, so resending an untouched one would
 *     rewrite work someone else just did.
 *   - Chips are edited as slugs; the server syncs joins from them and
 *     stamps confirmed/human. `confidence` is not editable here.
 */

export interface ItemDraft {
  name: string;
  description: string;
  sectionId: string;
  ingredientSlugs: string[];
  tagSlugs: string[];
  /** `currency` is carried, not edited — dropping it would rewrite a non-USD row to USD. */
  variants: Array<{ size: string; price: string; currency: string }>;
  modifiers: Array<{ name: string; kind: AdminModifierKind; price: string }>;
}

const MODIFIER_KINDS: readonly AdminModifierKind[] = ['addition', 'choice', 'side'];
const PRICE_INPUT = /^\d+(\.\d{1,2})?$/;

function toModifierKind(raw: string | undefined): AdminModifierKind {
  return MODIFIER_KINDS.find((kind) => kind === raw) ?? 'addition';
}

function centsToInput(cents: number | null | undefined): string {
  return cents == null ? '' : (cents / 100).toFixed(2);
}

export function draftFromItem(item: AdminItemRow): ItemDraft {
  return {
    name: item.name ?? '',
    description: item.description ?? '',
    sectionId: item.menu_section_id ?? '',
    ingredientSlugs: (item.ingredients ?? []).map((row) => row.slug ?? '').filter(Boolean),
    tagSlugs: (item.tags ?? []).map((row) => row.slug ?? '').filter(Boolean),
    variants: (item.variants ?? []).map((row) => ({
      size: row.size ?? '',
      price: centsToInput(row.price_cents),
      currency: row.currency ?? 'USD',
    })),
    modifiers: (item.modifiers ?? []).map((row) => ({
      name: row.name ?? '',
      kind: toModifierKind(row.kind),
      price: centsToInput(row.price_cents),
    })),
  };
}

export function draftBlockers(draft: ItemDraft): string | null {
  if (draft.name.trim() === '') return 'A dish needs a name.';
  const badPrice = [...draft.variants, ...draft.modifiers].some(
    (row) => row.price.trim() !== '' && !PRICE_INPUT.test(row.price.trim()),
  );
  if (badPrice) return 'Prices must look like 8 or 8.95.';
  if (draft.modifiers.some((row) => row.name.trim() === '')) return 'Every modifier needs a name.';
  return null;
}

/**
 * A size with no amount is a real menu row, so it survives; only a
 * wholly empty row is dropped. Anything the admin typed must reach the
 * server — silently discarding it would lose work behind a Save.
 */
function variantsPayload(draft: ItemDraft) {
  return draft.variants.flatMap((row) => {
    const price = row.price.trim();
    const size = row.size.trim();
    const cents = PRICE_INPUT.test(price) ? Math.round(Number(price) * 100) : null;
    if (cents === null && size === '') return [];
    return [{ size: size || null, price_cents: cents, currency: row.currency }];
  });
}

function modifiersPayload(draft: ItemDraft) {
  return draft.modifiers.flatMap((row) => {
    const name = row.name.trim();
    if (name === '') return [];
    const price = row.price.trim();
    return [
      {
        name,
        kind: row.kind,
        price_cents: PRICE_INPUT.test(price) ? Math.round(Number(price) * 100) : null,
      },
    ];
  });
}

/** Draft → PATCH body, omitting facets the user never touched. */
export function editsFromDraft(draft: ItemDraft, baseline: ItemDraft): AdminItemEdits {
  const edits: AdminItemEdits = {};
  if (draft.name.trim() !== baseline.name.trim()) edits.name = draft.name.trim();
  if (draft.description.trim() !== baseline.description.trim()) {
    // null clears the column; '' would store an empty string over NULL.
    edits.description = draft.description.trim() || null;
  }
  if (draft.sectionId !== baseline.sectionId) {
    edits.menu_section_id = draft.sectionId === '' ? null : draft.sectionId;
  }
  // Compared as JSON, not join() — a slug containing the separator would
  // otherwise compare equal to a different list and drop the edit.
  if (JSON.stringify(draft.ingredientSlugs) !== JSON.stringify(baseline.ingredientSlugs)) {
    edits.ingredient_slugs = draft.ingredientSlugs;
  }
  if (JSON.stringify(draft.tagSlugs) !== JSON.stringify(baseline.tagSlugs)) {
    edits.tag_slugs = draft.tagSlugs;
  }

  const variants = variantsPayload(draft);
  if (JSON.stringify(variants) !== JSON.stringify(variantsPayload(baseline))) {
    edits.variants = variants;
  }
  const modifiers = modifiersPayload(draft);
  if (JSON.stringify(modifiers) !== JSON.stringify(modifiersPayload(baseline))) {
    edits.modifiers = modifiers;
  }
  return edits;
}

export function ItemDeepEditPanel({
  itemId,
  draft,
  sections,
  busy,
  onChange,
  onCancel,
  onSave,
}: {
  itemId: string;
  draft: ItemDraft;
  sections?: Array<{ id: string; name: string; menuName: string }>;
  busy: boolean;
  onChange: (next: ItemDraft) => void;
  onCancel: () => void;
  onSave: () => void;
}) {
  const blocker = draftBlockers(draft);

  return (
    <div
      className="mt-bw-3 space-y-bw-3 border-t border-zinc-100 pt-bw-3 text-bw-sm"
      data-testid={`item-deep-edit-${itemId}`}
    >
      <div className="grid gap-bw-2 sm:grid-cols-2">
        <label className="flex flex-col gap-bw-1 text-zinc-600">
          Name
          <input
            value={draft.name}
            onChange={(e) => onChange({ ...draft, name: e.target.value })}
            data-testid={`item-name-${itemId}`}
            className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
          />
        </label>
        {sections && sections.length > 0 && (
          <label className="flex flex-col gap-bw-1 text-zinc-600">
            Section
            <select
              value={draft.sectionId}
              onChange={(e) => onChange({ ...draft, sectionId: e.target.value })}
              data-testid={`item-section-${itemId}`}
              className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
            >
              <option value="">— none —</option>
              {sections.map((section) => (
                <option key={section.id} value={section.id}>
                  {section.menuName} › {section.name}
                </option>
              ))}
            </select>
          </label>
        )}
        <label className="flex flex-col gap-bw-1 text-zinc-600 sm:col-span-2">
          Description
          <textarea
            value={draft.description}
            onChange={(e) => onChange({ ...draft, description: e.target.value })}
            rows={2}
            data-testid={`item-description-${itemId}`}
            className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
          />
        </label>
      </div>

      <ChipEditor
        label="Ingredients"
        testId={`ingredients-${itemId}`}
        slugs={draft.ingredientSlugs}
        onChange={(ingredientSlugs) => onChange({ ...draft, ingredientSlugs })}
        search={async (q) => {
          const rows = await searchIngredients(q);
          return rows.map((r) => ({ slug: r.slug, name: r.name }));
        }}
      />

      <ChipEditor
        label="Tags"
        testId={`tags-${itemId}`}
        slugs={draft.tagSlugs}
        onChange={(tagSlugs) => onChange({ ...draft, tagSlugs })}
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

      <div data-testid={`item-variants-${itemId}`}>
        <span className="text-zinc-600">Prices</span>
        <ul className="mt-bw-1 space-y-bw-1">
          {draft.variants.map((row, index) => (
            <li key={index} className="flex items-center gap-bw-2">
              <input
                value={row.size}
                onChange={(e) =>
                  onChange({
                    ...draft,
                    variants: draft.variants.map((r, i) =>
                      i === index ? { ...r, size: e.target.value } : r,
                    ),
                  })
                }
                placeholder="size (optional)"
                aria-label={`Size for price row ${index + 1}`}
                data-testid={`item-variant-size-${itemId}-${index}`}
                className="w-1/2 rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-xs"
              />
              <span className="text-bw-xs text-zinc-400">$</span>
              <input
                value={row.price}
                onChange={(e) =>
                  onChange({
                    ...draft,
                    variants: draft.variants.map((r, i) =>
                      i === index ? { ...r, price: e.target.value } : r,
                    ),
                  })
                }
                inputMode="decimal"
                placeholder="0.00"
                aria-label={`Amount for price row ${index + 1}`}
                data-testid={`item-variant-price-${itemId}-${index}`}
                className="w-24 rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-xs"
              />
              <button
                type="button"
                onClick={() =>
                  onChange({ ...draft, variants: draft.variants.filter((_, i) => i !== index) })
                }
                aria-label={`Remove price row ${index + 1}`}
                data-testid={`item-variant-remove-${itemId}-${index}`}
                className="text-bw-xs font-bold text-zinc-400 hover:text-danger"
              >
                ×
              </button>
            </li>
          ))}
        </ul>
        <button
          type="button"
          onClick={() =>
            onChange({
              ...draft,
              variants: [...draft.variants, { size: '', price: '', currency: 'USD' }],
            })
          }
          data-testid={`item-variant-add-${itemId}`}
          className="mt-bw-1 text-bw-xs font-semibold text-zinc-600 underline hover:text-zinc-900"
        >
          + Add a price
        </button>
      </div>

      <div data-testid={`item-modifiers-${itemId}`}>
        <span className="text-zinc-600">Add-ons &amp; options</span>
        <ul className="mt-bw-1 space-y-bw-1">
          {draft.modifiers.map((row, index) => (
            <li key={index} className="flex items-center gap-bw-2">
              <input
                value={row.name}
                onChange={(e) =>
                  onChange({
                    ...draft,
                    modifiers: draft.modifiers.map((r, i) =>
                      i === index ? { ...r, name: e.target.value } : r,
                    ),
                  })
                }
                placeholder="name"
                aria-label={`Name for add-on ${index + 1}`}
                data-testid={`item-modifier-name-${itemId}-${index}`}
                className="w-1/2 rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-xs"
              />
              <select
                value={row.kind}
                onChange={(e) =>
                  onChange({
                    ...draft,
                    modifiers: draft.modifiers.map((r, i) =>
                      i === index ? { ...r, kind: toModifierKind(e.target.value) } : r,
                    ),
                  })
                }
                aria-label={`Kind for add-on ${index + 1}`}
                data-testid={`item-modifier-kind-${itemId}-${index}`}
                className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-xs"
              >
                {MODIFIER_KINDS.map((kind) => (
                  <option key={kind} value={kind}>
                    {kind}
                  </option>
                ))}
              </select>
              <input
                value={row.price}
                onChange={(e) =>
                  onChange({
                    ...draft,
                    modifiers: draft.modifiers.map((r, i) =>
                      i === index ? { ...r, price: e.target.value } : r,
                    ),
                  })
                }
                inputMode="decimal"
                placeholder="0.00"
                aria-label={`Price for add-on ${index + 1}`}
                data-testid={`item-modifier-price-${itemId}-${index}`}
                className="w-20 rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-xs"
              />
              <button
                type="button"
                onClick={() =>
                  onChange({ ...draft, modifiers: draft.modifiers.filter((_, i) => i !== index) })
                }
                aria-label={`Remove add-on ${index + 1}`}
                data-testid={`item-modifier-remove-${itemId}-${index}`}
                className="text-bw-xs font-bold text-zinc-400 hover:text-danger"
              >
                ×
              </button>
            </li>
          ))}
        </ul>
        <button
          type="button"
          onClick={() =>
            onChange({
              ...draft,
              modifiers: [...draft.modifiers, { name: '', kind: 'addition', price: '' }],
            })
          }
          data-testid={`item-modifier-add-${itemId}`}
          className="mt-bw-1 text-bw-xs font-semibold text-zinc-600 underline hover:text-zinc-900"
        >
          + Add an option
        </button>
      </div>

      <div className="flex items-center justify-between gap-bw-3">
        {blocker ? (
          <p
            role="alert"
            data-testid={`item-blocker-${itemId}`}
            className="text-bw-xs text-red-700"
          >
            {blocker}
          </p>
        ) : (
          <span />
        )}
        <span className="flex items-center gap-bw-3">
          <button
            type="button"
            onClick={onCancel}
            data-testid={`item-cancel-${itemId}`}
            className="text-bw-xs font-semibold text-zinc-500 underline hover:text-zinc-800"
          >
            Discard changes
          </button>
          <button
            type="button"
            onClick={onSave}
            disabled={busy || blocker !== null}
            data-testid={`item-save-${itemId}`}
            className="rounded-bw-md bg-bite px-bw-3 py-bw-1 font-semibold text-white disabled:opacity-50"
          >
            {busy ? 'Saving…' : 'Save'}
          </button>
        </span>
      </div>
    </div>
  );
}

let tagCatalog: Promise<TasteTag[]> | null = null;
function loadTagCatalog(): Promise<TasteTag[]> {
  tagCatalog ??= fetchTags([]).catch((e: unknown) => {
    tagCatalog = null;
    throw e;
  });
  return tagCatalog;
}

const SEARCH_DEBOUNCE_MS = 250;

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
  search: (q: string) => Promise<Array<{ slug: string; name: string }>>;
}) {
  const [query, setQuery] = useState('');
  const [options, setOptions] = useState<Array<{ slug: string; name: string }>>([]);
  const seq = useRef(0);

  useEffect(() => {
    const mine = ++seq.current;
    if (query.trim().length < 2) {
      setOptions([]);
      return;
    }
    const timer = setTimeout(() => {
      search(query)
        .then((rows) => {
          if (mine === seq.current) setOptions(rows);
        })
        .catch(() => {
          if (mine === seq.current) setOptions([]);
        });
    }, SEARCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
    // `search` is rebuilt per render by the parent; depending on it
    // would refetch on unrelated keystrokes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query]);

  const suggestions = options.filter((option) => !slugs.includes(option.slug));

  return (
    <div data-testid={`edit-${testId}`}>
      <span className="text-zinc-600">{label}</span>
      <p className="mt-bw-1 flex flex-wrap gap-bw-1">
        {slugs.map((slug) => (
          <span
            key={slug}
            className="inline-flex items-center gap-1 rounded-bw-pill bg-zinc-100 px-bw-2 py-0.5 text-bw-xs text-zinc-700"
          >
            {slug}
            <button
              type="button"
              onClick={() => onChange(slugs.filter((s) => s !== slug))}
              aria-label={`Remove ${slug}`}
              data-testid={`remove-${testId}-${slug}`}
              className="font-bold text-zinc-400 hover:text-danger"
            >
              ×
            </button>
          </span>
        ))}
        {slugs.length === 0 && <span className="text-bw-xs italic text-zinc-400">none</span>}
      </p>
      <input
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder={`Add ${label.toLowerCase()}…`}
        aria-label={`Search ${label.toLowerCase()} to add`}
        data-testid={`search-${testId}`}
        className="mt-bw-1 w-full rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-xs"
      />
      {suggestions.length > 0 && (
        <ul className="mt-bw-1 max-h-32 overflow-y-auto rounded-bw-md border border-zinc-200">
          {suggestions.map((option) => (
            <li key={option.slug}>
              <button
                type="button"
                onClick={() => {
                  onChange([...slugs, option.slug]);
                  setQuery('');
                  setOptions([]);
                }}
                data-testid={`add-${testId}-${option.slug}`}
                className="block w-full px-bw-2 py-bw-1 text-left text-bw-xs hover:bg-zinc-50"
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
