/**
 * Phase 3.6 — apply session-only "show anyway" overrides.
 * Mirror of apps/mobile/lib/restaurant-overrides.ts; see that file
 * for the design rationale.
 */
import type { FilteredItem, ItemSection } from './restaurants';

export function applyOverrides(
  sections: ItemSection[],
  shownAnyway: Set<string>,
): ItemSection[] {
  if (shownAnyway.size === 0) return sections;
  return sections.map((section) => {
    const stillHidden: FilteredItem[] = [];
    const promoted: FilteredItem[] = [];
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
