'use client';

import { useState } from 'react';
import { hiddenReasonLabel, type HideReason, type ItemSection } from '@biteworthy/filter-engine';
import type { RestaurantItem } from '../../../lib/restaurants';
import { ItemRow } from './ItemRow';

/**
 * Extracted from RestaurantClient (menu-page hierarchy pass) — the
 * per-section grid of items (visible + collapsible hidden), moved out
 * unchanged.
 */

export function HiddenReasonChip({ reason }: { reason: HideReason }) {
  return (
    <span
      data-testid={`chip-${reason.kind}`}
      className="rounded-bw-pill border border-zinc-200 bg-zinc-50 px-bw-2 py-bw-0_5 text-bw-xs font-semibold text-hide"
    >
      {hiddenReasonLabel(reason)}
    </span>
  );
}

// Exported for render tests, like the other section-level helpers.
export function SectionBlock({
  section,
  showHeading = true,
  restaurantSlug,
  presetSlug,
  shownAnyway,
  onToggleOverride,
  onSetPersistentOverride,
}: {
  section: ItemSection<RestaurantItem>;
  showHeading?: boolean;
  restaurantSlug: string;
  presetSlug: string | null;
  shownAnyway: Set<string>;
  onToggleOverride: (itemId: string) => void;
  onSetPersistentOverride: (itemId: string, next: boolean) => void;
}) {
  const [hiddenOpen, setHiddenOpen] = useState(false);
  return (
    // When the heading is suppressed the aria-label keeps the region
    // reachable by landmark for screen-reader users.
    <section className="mt-bw-6" aria-label={showHeading ? undefined : 'Menu'}>
      {showHeading && <h2 className="text-bw-lg font-bold">{section.name}</h2>}
      {/* items-start: a photo card must not stretch its photo-less row
          siblings into 160px of empty card once real photos land. */}
      <ul className="mt-bw-2 grid grid-cols-1 items-start gap-bw-4 sm:grid-cols-2 lg:grid-cols-3">
        {section.visible.map((item) => (
          <ItemRow
            key={item.id}
            item={item}
            restaurantSlug={restaurantSlug}
            presetSlug={presetSlug}
            overridden={shownAnyway.has(item.id) || item.overridden_by_user === true}
            onToggleOverride={onToggleOverride}
            onSetPersistentOverride={onSetPersistentOverride}
          />
        ))}
        {section.visible.length === 0 && section.hidden.length > 0 && (
          <li className="col-span-full py-bw-2 text-bw-sm text-zinc-500">
            {/* "here", not "in this section" — the heading may be suppressed. */}
            Every item here is hidden by your filter.
          </li>
        )}
      </ul>

      {section.hidden.length > 0 && (
        <button
          type="button"
          onClick={() => setHiddenOpen((v) => !v)}
          aria-expanded={hiddenOpen}
          aria-controls={`hidden-${section.id ?? 'none'}`}
          className="mt-bw-2 text-bw-sm font-semibold text-bite hover:text-bite-dark"
        >
          {hiddenOpen ? '▾ Hide' : '▸ Show'} items hidden by your filter ({section.hidden.length})
        </button>
      )}

      {hiddenOpen && (
        <ul
          id={`hidden-${section.id ?? 'none'}`}
          className="mt-bw-2 grid grid-cols-1 gap-bw-4 sm:grid-cols-2 lg:grid-cols-3"
        >
          {section.hidden.map((item) => (
            <ItemRow
              key={item.id}
              item={item}
              restaurantSlug={restaurantSlug}
              presetSlug={presetSlug}
              hidden
              overridden={false}
              onToggleOverride={onToggleOverride}
              onSetPersistentOverride={onSetPersistentOverride}
            />
          ))}
        </ul>
      )}
    </section>
  );
}

/**
 * The full menu — every section block, or the "no published items"
 * empty state when the restaurant has none at all.
 */
export function SectionList({
  sections,
  restaurantSlug,
  presetSlug,
  shownAnyway,
  onToggleOverride,
  onSetPersistentOverride,
}: {
  sections: ItemSection<RestaurantItem>[];
  restaurantSlug: string;
  presetSlug: string | null;
  shownAnyway: Set<string>;
  onToggleOverride: (itemId: string) => void;
  onSetPersistentOverride: (itemId: string, next: boolean) => void;
}) {
  // A lone group wearing the grouping fallback label means the menu has
  // no course structure — an "Other" heading over everything would be
  // labeling noise. Keyed on the name, not the id: groupItemsBySection
  // mints 'Other' from a missing menu_section_name whatever the id is.
  const loneFallbackSection = sections.length === 1 && sections[0]?.name === 'Other';

  if (sections.length === 0) {
    return (
      <p className="mt-bw-6 text-center text-bw-base text-zinc-500">
        No published items at this restaurant yet.
      </p>
    );
  }

  return (
    <>
      {sections.map((section) => (
        <SectionBlock
          key={section.id ?? '__none__'}
          section={section}
          showHeading={!loneFallbackSection}
          restaurantSlug={restaurantSlug}
          presetSlug={presetSlug}
          shownAnyway={shownAnyway}
          onToggleOverride={onToggleOverride}
          onSetPersistentOverride={onSetPersistentOverride}
        />
      ))}
    </>
  );
}
