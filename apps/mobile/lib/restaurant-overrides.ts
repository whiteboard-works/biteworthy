/**
 * Phase 3.4 — apply session-only "show anyway" overrides to grouped
 * restaurant items. Pure helper so the screen stays small and the
 * test suite doesn't need to mount React Native.
 *
 * Items in `shownAnyway` are moved from each section's `hidden`
 * bucket into its `visible` bucket. The underlying item still
 * carries `status: "hidden"` and its reasons[]; the chip UI keeps
 * showing them so the override is transparent to the user.
 */
import type { FilteredItem, ItemSection } from './api/restaurants';

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
