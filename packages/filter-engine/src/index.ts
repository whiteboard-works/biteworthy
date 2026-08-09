/**
 * BiteWorthy filter engine — the wire types and presentation helpers
 * every TS surface shares when it renders a filtered menu.
 *
 * **The filter itself is not here, and there is only one of it.** The
 * Rails endpoint at `GET /api/v1/restaurants/:id/items` (and the
 * `get_menu` tool behind it) decides `status` / `reasons` per item;
 * `Menus::Filter#reasons_for` is the only implementation. Clients
 * render what they receive and never recompute it.
 *
 * That is deliberate. The decision needs the taxonomy — the tree is
 * hierarchical, `dairy` has ninety descendants with `dairy.cheddar`
 * among them, and `Menus::Subtree` expands an avoided node into its
 * subtree before any comparison happens. A client does not have the
 * taxonomy, so a client-side copy would under-filter: a person
 * avoiding `dairy` would be shown a dish tagged `dairy-cheddar` as
 * safe. A hand-mirrored copy of the rule also has to be kept in
 * lockstep by hand, and this repo carried one for months that no
 * screen ever called.
 *
 * If a client-side re-filter is ever genuinely wanted (say, to switch
 * preset without a roundtrip), the bar is a real shared fixture
 * generated from `Menus::Query#serialize` that both suites assert
 * against — the way `fixtures/taste-parity.json` pins `TasteScoring`.
 * A TS test that builds its own expectations in TS proves nothing.
 *
 * Naming uses snake_case to match the wire format. Conversion to
 * camelCase happens at UI boundaries if needed.
 */

import type { Strictness, Confidence } from '@biteworthy/api-types';

// ─── Wire-format types ──────────────────────────────────────────────

// Strictness + Confidence are the canonical wire enums — declared once
// in @biteworthy/api-types (codegen-anchored) and re-exported here so
// every consumer keeps importing the filter contract from one place.
export type { Strictness, Confidence };

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
  /**
   * Phase 4.2 — true when the authenticated user has flagged this
   * item as "never hide for me." Optional so anonymous responses
   * (which always set it `false` server-side) don't have to spell it
   * out, and so factories / fixtures can omit it in tests that don't
   * exercise the override path.
   */
  overridden_by_user?: boolean;
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
  // Phase 4.2 — items the server already marked `overridden_by_user`
  // get the same treatment as session-only "show anyway" picks: they
  // move from `hidden` to `visible`. The `shownAnyway` set is unioned
  // with the per-item flag so callers don't have to merge manually.
  const hasPersistentOverrides = sections.some((s) => s.hidden.some((i) => i.overridden_by_user));
  if (shownAnyway.size === 0 && !hasPersistentOverrides) return sections;

  return sections.map((section) => {
    const stillHidden: T[] = [];
    const promoted: T[] = [];
    for (const item of section.hidden) {
      if (shownAnyway.has(item.id) || item.overridden_by_user) promoted.push(item);
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
  tasteStateOf,
  toProfilePayload,
  toTastePayload,
  type DietaryPreset,
  type DraftProfile,
  type OnboardingAction,
  type TasteState,
} from './onboarding-reducer';

// ─── Top Picks selection over server-supplied scores (Phase 8.4) ───

export {
  tasteReasonLine,
  topPicksFromScores,
  MIN_POSITIVE_PICKS,
  TOP_PICKS_COUNT,
  type ScoredWireItem,
  type TasteReason,
} from './taste';

// ─── Shareable profile tokens (Phase 3.9) ──────────────────────────

export { encodeProfileToken, PROFILE_TOKEN_VERSION, type ShareableProfile } from './profile-token';
