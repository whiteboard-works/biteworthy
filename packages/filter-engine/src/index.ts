/**
 * BiteWorthy filter engine — single source of truth for the per-item
 * filter computation that runs on web, mobile, and (in spec form)
 * the Rails API.
 *
 * The Rails endpoint at `GET /api/v1/restaurants/:id/items` is the
 * canonical producer of `FilteredItem` (Phase 1.7 + 3.4). This
 * package is the canonical *consumer* shape — every TS surface that
 * binds to the items endpoint imports its types from here. The
 * `applyProfile` function below produces the same payload shape the
 * Rails serializer emits, so a client can recompute hidden/visible
 * locally (e.g. when the user picks a different preset) without a
 * roundtrip and the snapshots stay byte-identical.
 *
 * Naming uses snake_case to match the wire format. Conversion to
 * camelCase happens at UI boundaries if needed.
 */

// ─── Wire-format types ──────────────────────────────────────────────

export type Strictness = 'relaxed' | 'balanced' | 'strict';
export type Confidence = 'confirmed' | 'suggested' | 'inferred';
export type ItemStatus = 'visible' | 'hidden';

/**
 * Discriminated union covering every reason an item can be hidden.
 * Reasons are enriched with display strings (`*_name`, `*_family`)
 * so the UI chip is a pure render — the client never has to look up
 * names separately.
 */
export type HideReason =
  | {
      kind: 'avoid_ingredient';
      ingredient_id: string;
      ingredient_name: string | null;
      ingredient_family: string | null;
    }
  | {
      kind: 'avoid_tag';
      tag_id: string;
      tag_name: string | null;
      tag_family: string | null;
    }
  | { kind: 'unconfirmed_strict'; confidence: string };

/**
 * Minimum item shape the filter operates on. The Rails serializer
 * emits a superset (popularity, description, etc.) — those flow
 * through unchanged.
 */
export interface FilterableItem {
  id: string;
  ingredient_ids: string[];
  tag_ids: string[];
  confidence: Confidence;
  menu_section_id?: string | null;
  menu_section_name?: string | null;
}

export interface FilteredItem extends FilterableItem {
  status: ItemStatus;
  reasons: HideReason[];
}

/**
 * The filter contract. Avoid lists + strictness — exactly the inputs
 * the Rails `Filter` struct holds. `prefer_tag_ids` lives on the
 * profile too but only affects sort order (server-side); the engine
 * exposes it so callers can wire it in without churn.
 */
export interface FilterProfile {
  avoid_ingredient_ids: string[];
  avoid_tag_ids: string[];
  prefer_tag_ids?: string[];
  strictness: Strictness;
}

/**
 * Lookup tables for the chip enrichment. Pre-computed by the caller
 * (one fetch per ingredient/tag id, batched). Same shape Rails
 * builds in `ItemsController#build_label_lookup`.
 */
export interface LabelLookup {
  ingredients?: Record<string, { name: string | null; family: string | null }>;
  tags?: Record<string, { name: string | null; family: string | null }>;
}

// ─── Core filter computation ───────────────────────────────────────

/**
 * Mark each item visible/hidden under `profile` and emit the same
 * `reasons[]` payload the Rails serializer would. Pure function.
 *
 * `labels` is optional — when omitted, reasons still carry ids but
 * `*_name` and `*_family` come back as null. UI fallbacks render
 * "Contains restricted (ingredient)" in that case.
 */
export function applyProfile<T extends FilterableItem>(
  items: T[],
  profile: FilterProfile,
  labels: LabelLookup = {},
): (T & FilteredItem)[] {
  const avoidIngredients = new Set(profile.avoid_ingredient_ids);
  const avoidTags = new Set(profile.avoid_tag_ids);
  const ingredientLabels = labels.ingredients ?? {};
  const tagLabels = labels.tags ?? {};

  return items.map((item) => {
    const reasons: HideReason[] = [];

    for (const ing of item.ingredient_ids) {
      if (!avoidIngredients.has(ing)) continue;
      const label = ingredientLabels[ing] ?? null;
      reasons.push({
        kind: 'avoid_ingredient',
        ingredient_id: ing,
        ingredient_name: label?.name ?? null,
        ingredient_family: label?.family ?? null,
      });
    }
    for (const tag of item.tag_ids) {
      if (!avoidTags.has(tag)) continue;
      const label = tagLabels[tag] ?? null;
      reasons.push({
        kind: 'avoid_tag',
        tag_id: tag,
        tag_name: label?.name ?? null,
        tag_family: label?.family ?? null,
      });
    }
    if (profile.strictness === 'strict' && item.confidence !== 'confirmed') {
      reasons.push({ kind: 'unconfirmed_strict', confidence: item.confidence });
    }

    return {
      ...item,
      status: reasons.length === 0 ? ('visible' as const) : ('hidden' as const),
      reasons,
    };
  });
}

/**
 * Build a `LabelLookup` from a flat array of records — what the
 * caller usually has after a bulk fetch (`Ingredient.where(id: ids).pluck(...)`
 * on the API side, or a flat JSON lookup on the client).
 */
export function buildLabelLookup(args: {
  ingredients?: Array<{ id: string; name: string | null; path?: string | null }>;
  tags?: Array<{ id: string; name: string | null; family?: string | null }>;
}): LabelLookup {
  const out: LabelLookup = {};
  if (args.ingredients) {
    out.ingredients = {};
    for (const i of args.ingredients) {
      out.ingredients[i.id] = {
        name: i.name,
        // Rails derives family from ltree's first segment
        // (e.g. "dairy.cheddar" -> "dairy"). Mirror that here so
        // either side can build a lookup from raw ingredient rows.
        family: typeof i.path === 'string' ? (i.path.split('.')[0] ?? null) : null,
      };
    }
  }
  if (args.tags) {
    out.tags = {};
    for (const t of args.tags) {
      out.tags[t.id] = { name: t.name, family: t.family ?? null };
    }
  }
  return out;
}

// ─── Display helpers (single source of truth for chip strings) ─────

function humanizeFamily(family: string | null | undefined): string {
  if (!family) return 'restricted';
  return family.replace(/_/g, ' ');
}

export function hiddenReasonLabel(reason: HideReason): string {
  switch (reason.kind) {
    case 'avoid_ingredient': {
      const family = humanizeFamily(reason.ingredient_family);
      const name = reason.ingredient_name ?? 'ingredient';
      return `Contains ${family} (${name})`;
    }
    case 'avoid_tag': {
      const family = humanizeFamily(reason.tag_family);
      const name = reason.tag_name ?? 'tag';
      return `Tagged ${family}: ${name}`;
    }
    case 'unconfirmed_strict':
      return `AI confidence: ${reason.confidence} (strict mode)`;
  }
}

export function hiddenReasonHeadline(reasons: HideReason[]): string {
  if (reasons.length === 0) return '';
  const first = reasons[0]!;
  const more = reasons.length - 1;
  const suffix = more > 0 ? ` (+${more} more)` : '';
  return `Hidden — ${hiddenReasonLabel(first)}${suffix}`;
}

// ─── Section grouping (shared by web + mobile screens) ─────────────

export interface ItemSection<T extends FilteredItem = FilteredItem> {
  id: string | null;
  name: string;
  visible: T[];
  hidden: T[];
}

export function groupItemsBySection<T extends FilteredItem>(items: T[]): ItemSection<T>[] {
  const order: (string | null)[] = [];
  const lookup = new Map<string | null, ItemSection<T>>();

  for (const item of items) {
    const sectionId = item.menu_section_id ?? null;
    let section = lookup.get(sectionId);
    if (!section) {
      section = {
        id: sectionId,
        name: item.menu_section_name ?? 'Other',
        visible: [],
        hidden: [],
      };
      lookup.set(sectionId, section);
      order.push(sectionId);
    }
    if (item.status === 'visible') section.visible.push(item);
    else section.hidden.push(item);
  }

  return order.map((id) => lookup.get(id)!);
}

// ─── Session-only "show anyway" override ───────────────────────────

export function applyOverrides<T extends FilteredItem>(
  sections: ItemSection<T>[],
  shownAnyway: ReadonlySet<string>,
): ItemSection<T>[] {
  if (shownAnyway.size === 0) return sections;
  return sections.map((section) => {
    const stillHidden: T[] = [];
    const promoted: T[] = [];
    for (const item of section.hidden) {
      if (shownAnyway.has(item.id)) promoted.push(item);
      else stillHidden.push(item);
    }
    if (promoted.length === 0) return section;
    return {
      ...section,
      visible: [...section.visible, ...promoted],
      hidden: stillHidden,
    };
  });
}

// ─── Onboarding draft profile (Phase 3.2 + 3.8) ────────────────────

export {
  initialDraft,
  onboardingReducer,
  toProfilePayload,
  type DietaryPreset,
  type DraftProfile,
  type OnboardingAction,
} from './onboarding-reducer';

// ─── Shareable profile tokens (Phase 3.9) ──────────────────────────

export {
  decodeProfileToken,
  encodeProfileToken,
  shareableToFilterProfile,
  PROFILE_TOKEN_VERSION,
  InvalidProfileTokenError,
  type ShareableProfile,
} from './profile-token';
