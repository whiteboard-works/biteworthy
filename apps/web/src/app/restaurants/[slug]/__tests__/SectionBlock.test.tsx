import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { SectionBlock } from '../RestaurantClient';
import type { RestaurantItem } from '../../../../lib/restaurants';
import type { ItemSection } from '@biteworthy/filter-engine';

vi.mock('../../../_PostHogProvider', () => ({
  useTracker: () => ({ track: vi.fn() }),
}));

// The lone-"Other" heading suppression is the only behavior change this
// component got in the compact-cards pass; pin both directions so the
// predicate can't silently invert.
describe('SectionBlock — heading', () => {
  const item = (over: Partial<RestaurantItem>): RestaurantItem => ({
    id: 'i-1',
    restaurant_id: 'r-1',
    name: 'Pad Thai',
    description: '',
    confidence: 'confirmed',
    ingredient_ids: [],
    tag_ids: [],
    menu_section_id: null,
    menu_section_name: null,
    status: 'visible',
    reasons: [],
    photo_url: null,
    ...over,
  });

  const renderSection = (section: ItemSection<RestaurantItem>, showHeading: boolean) =>
    render(
      <SectionBlock
        section={section}
        showHeading={showHeading}
        restaurantSlug="zia"
        presetSlug={null}
        shownAnyway={new Set()}
        onToggleOverride={vi.fn()}
        onSetPersistentOverride={vi.fn()}
      />,
    );

  it('suppresses the heading and labels the region for assistive tech', () => {
    renderSection({ id: null, name: 'Other', visible: [item({})], hidden: [] }, false);
    expect(screen.queryByRole('heading')).not.toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'Menu' })).toBeInTheDocument();
  });

  it('renders a real section heading when not suppressed', () => {
    renderSection({ id: 's-1', name: 'Entrees', visible: [item({})], hidden: [] }, true);
    expect(screen.getByRole('heading', { name: 'Entrees' })).toBeInTheDocument();
  });
});
