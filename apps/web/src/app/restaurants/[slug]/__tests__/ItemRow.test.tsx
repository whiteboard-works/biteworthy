import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ItemRow } from '../ItemRow';
import type { RestaurantItem } from '../../../../lib/restaurants';

/**
 * Phase 4.11.4 deferred snapshot — finally landing.
 *
 * Covers the photo_url contract added in PR #169: `<img>` appears
 * with src=photo_url when the field is set; doesn't render when null.
 * Plus a few sibling tests so future ItemRow changes don't drift.
 */

const baseItem: RestaurantItem = {
  id: 'item-1',
  restaurant_id: 'rest-1',
  name: 'Pad Thai',
  description: 'Rice noodles, peanut, lime.',
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
    <ul>
      <ItemRow
        item={{ ...baseItem, ...item }}
        restaurantSlug="cream-bean-berry"
        overridden={false}
        onToggleOverride={vi.fn()}
        onSetPersistentOverride={vi.fn()}
      />
    </ul>,
  );
}

describe('ItemRow — photo_url contract (Phase 4.11.4)', () => {
  it('renders the dish photo when photo_url is set', () => {
    renderRow({
      photo_url: 'https://api.bite-worthy.com/rails/active_storage/blobs/abc/dish-1.jpg',
    });

    const img = screen.getByTestId('item-photo-item-1');
    expect(img).toBeInTheDocument();
    expect(img).toHaveAttribute(
      'src',
      'https://api.bite-worthy.com/rails/active_storage/blobs/abc/dish-1.jpg',
    );
    expect(img).toHaveAttribute('alt', 'Pad Thai');
    expect(img).toHaveAttribute('loading', 'lazy');
  });

  it('does not render the dish photo when photo_url is null', () => {
    renderRow({ photo_url: null });
    expect(screen.queryByTestId('item-photo-item-1')).not.toBeInTheDocument();
  });
});

describe('ItemRow — placeholder photo', () => {
  // Every card fills its photo slot: a real photo when we have one,
  // otherwise a monogram placeholder so the grid never shows empty
  // gaps. The two are mutually exclusive.
  it('renders a monogram placeholder when photo_url is null', () => {
    renderRow({ photo_url: null });
    const placeholder = screen.getByTestId('item-photo-placeholder-item-1');
    expect(placeholder).toBeInTheDocument();
    // Monogram is the dish name's first letter, uppercased.
    expect(placeholder).toHaveTextContent('P');
    // Labelled for assistive tech, since it stands in for the photo.
    expect(placeholder).toHaveAttribute('role', 'img');
    expect(placeholder).toHaveAttribute('aria-label', expect.stringContaining('Pad Thai'));
  });

  it('renders the real photo and no placeholder when photo_url is set', () => {
    renderRow({ photo_url: 'https://example.test/dish.jpg' });
    expect(screen.getByTestId('item-photo-item-1')).toBeInTheDocument();
    expect(screen.queryByTestId('item-photo-placeholder-item-1')).not.toBeInTheDocument();
  });
});

describe('ItemRow — name + description + open link', () => {
  it('renders the item name + description', () => {
    renderRow({});
    expect(screen.getByText('Pad Thai')).toBeInTheDocument();
    expect(screen.getByText('Rice noodles, peanut, lime.')).toBeInTheDocument();
  });

  it('omits the description paragraph when empty', () => {
    renderRow({ description: '' });
    expect(screen.queryByText('Rice noodles, peanut, lime.')).not.toBeInTheDocument();
  });

  it('encodes the slug + id in the open-item link', () => {
    renderRow({});
    const link = screen.getByTestId('open-item-item-1');
    expect(link).toHaveAttribute('href', '/restaurants/cream-bean-berry/items/item-1');
  });

  it('shows "Be the first to review" when reviews_count is 0 / undefined', () => {
    renderRow({});
    expect(screen.getByTestId('open-item-item-1')).toHaveTextContent('Be the first to review');
  });

  it('pluralizes the reviews badge correctly', () => {
    renderRow({ reviews_count: 1 });
    expect(screen.getByTestId('open-item-item-1')).toHaveTextContent('1 review →');

    renderRow({ id: 'item-2', reviews_count: 3 });
    expect(screen.getByTestId('open-item-item-2')).toHaveTextContent('3 reviews →');
  });
});
