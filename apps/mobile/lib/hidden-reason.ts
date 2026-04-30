/**
 * Phase 3.4 — translate the {kind, *_id, *_name, *_family} reason
 * shape from the items endpoint into a human chip label.
 *
 * Pure function so tests can lock the strings down without mounting
 * React. The screen wraps the result in a styled chip; the web app
 * (Phase 3.6) will reuse this same helper.
 */
import type { HideReason } from './api/restaurants';

/** Family slugs use snake_case (e.g. `tree_nut`). Display in regular words. */
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

/** A short headline for the row when there's no room for the full chip list. */
export function hiddenReasonHeadline(reasons: HideReason[]): string {
  if (reasons.length === 0) return '';
  const first = reasons[0]!;
  const more = reasons.length - 1;
  const suffix = more > 0 ? ` (+${more} more)` : '';
  return `Hidden — ${hiddenReasonLabel(first)}${suffix}`;
}
