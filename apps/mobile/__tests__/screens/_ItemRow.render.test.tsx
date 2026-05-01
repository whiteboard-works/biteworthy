// Mock expo-router so importing the screen module (via the
// HiddenReasonChip re-export) doesn't pull the full Stack/Tabs
// runtime — same pattern as restaurant-screen.render.test.tsx.
jest.mock('expo-router', () => ({
  router: { push: jest.fn(), replace: jest.fn(), back: jest.fn() },
  useLocalSearchParams: () => ({}),
  Link: 'Link',
}));

// Mock expo-image to a plain string component so we can target
// it via testID + props without booting the native image module.
jest.mock('expo-image', () => ({
  Image: 'Image',
}));

import { render, screen } from '@testing-library/react-native';
import { ItemRow } from '../../app/restaurants/_ItemRow';
import type { RestaurantItem } from '../../lib/api/restaurants';

/**
 * Phase 4.11.4 deferred snapshot — finally landing (mobile side).
 *
 * Mirrors `apps/web/src/app/restaurants/[slug]/__tests__/ItemRow.test.tsx`
 * (PR #190). Covers the photo_url contract added in PR #169:
 * `<Image>` renders with `source.uri = photo_url` when set; doesn't
 * render when null. Plus a few sibling tests so future ItemRow
 * changes don't drift.
 */

const baseItem: RestaurantItem = {
  id: 'item-1',
  restaurant_id: 'rest-1',
  name: 'Pad Thai',
  description: 'Rice noodles, peanut, lime.',
  popularity: 0,
  confidence: 'confirmed',
  ingredient_ids: [],
  tag_ids: [],
  menu_section_id: null,
  menu_section_name: null,
  status: 'visible',
  reasons: [],
  photo_url: null,
};

function renderRow(item: Partial<RestaurantItem>) {
  return render(
    <ItemRow
      item={{ ...baseItem, ...item }}
      overridden={false}
      onToggleOverride={() => {}}
      onSetPersistentOverride={() => {}}
      allowPersistent={false}
    />,
  );
}

describe('ItemRow — photo_url contract (Phase 4.11.4, mobile)', () => {
  it('renders the dish photo when photo_url is set', () => {
    renderRow({
      photo_url: 'https://api.bite-worthy.com/rails/active_storage/blobs/abc/dish-1.jpg',
    });

    const img = screen.getByTestId('item-photo-item-1');
    expect(img).toBeOnTheScreen();
    expect(img.props.source).toEqual({
      uri: 'https://api.bite-worthy.com/rails/active_storage/blobs/abc/dish-1.jpg',
    });
    expect(img.props.accessibilityLabel).toBe('photo of Pad Thai');
    expect(img.props.contentFit).toBe('cover');
  });

  it('does not render the dish photo when photo_url is null', () => {
    renderRow({ photo_url: null });
    expect(screen.queryByTestId('item-photo-item-1')).toBeNull();
  });
});

describe('ItemRow — name + description + open badge (mobile)', () => {
  it('renders the item name + description', () => {
    renderRow({});
    expect(screen.getByText('Pad Thai')).toBeOnTheScreen();
    expect(screen.getByText('Rice noodles, peanut, lime.')).toBeOnTheScreen();
  });

  it('omits the description Text node when empty', () => {
    renderRow({ description: '' });
    expect(screen.queryByText('Rice noodles, peanut, lime.')).toBeNull();
  });

  it('shows "Be the first to review" when reviews_count is 0 / undefined', () => {
    renderRow({});
    expect(screen.getByText('Be the first to review')).toBeOnTheScreen();
  });

  it('pluralizes the reviews badge correctly', () => {
    renderRow({ reviews_count: 1 });
    expect(screen.getByText('1 review →')).toBeOnTheScreen();
  });

  it('pluralizes the reviews badge for >1', () => {
    renderRow({ reviews_count: 3 });
    expect(screen.getByText('3 reviews →')).toBeOnTheScreen();
  });
});
