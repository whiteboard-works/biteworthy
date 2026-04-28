import type { Confidence, Item, UserProfile } from '@biteworthy/api-types';

export type FilterReason =
  | { kind: 'avoid-ingredient'; ingredientId: string }
  | { kind: 'avoid-tag'; tagId: string }
  | { kind: 'unconfirmed-strict' };

export interface FilteredItem {
  item: Item;
  hidden: boolean;
  reasons: FilterReason[];
  preferMatchCount: number;
}

/**
 * Apply a UserProfile to a list of items. Pure function — same logic runs on
 * web, mobile, and (eventually) the Rails API for SSR consistency.
 *
 * Hidden items are returned alongside visible ones with `hidden: true` and a
 * machine-readable reason list, so the UI can render "Hidden — contains
 * dairy" with a one-tap override. Trust is the product.
 */
export function applyProfile(items: Item[], profile: UserProfile): FilteredItem[] {
  const avoidIngredients = new Set(profile.avoidIngredientIds);
  const avoidTags = new Set(profile.avoidTagIds);
  const preferTags = new Set(profile.preferTagIds);

  return items.map((item) => {
    const reasons: FilterReason[] = [];

    for (const id of item.ingredientIds) {
      if (avoidIngredients.has(id)) reasons.push({ kind: 'avoid-ingredient', ingredientId: id });
    }
    for (const id of item.tagIds) {
      if (avoidTags.has(id)) reasons.push({ kind: 'avoid-tag', tagId: id });
    }
    if (profile.strictness === 'strict' && !isConfirmed(item.confidence)) {
      reasons.push({ kind: 'unconfirmed-strict' });
    }

    const preferMatchCount = item.tagIds.reduce(
      (n, id) => (preferTags.has(id) ? n + 1 : n),
      0,
    );

    return { item, hidden: reasons.length > 0, reasons, preferMatchCount };
  });
}

export function sortFiltered(filtered: FilteredItem[]): FilteredItem[] {
  return [...filtered].sort((a, b) => {
    if (a.hidden !== b.hidden) return a.hidden ? 1 : -1;
    return b.preferMatchCount - a.preferMatchCount;
  });
}

function isConfirmed(c: Confidence): boolean {
  return c === 'confirmed';
}
