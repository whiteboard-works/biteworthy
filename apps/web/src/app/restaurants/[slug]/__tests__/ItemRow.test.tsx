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

describe('ItemRow — no placeholder tile', () => {
  // The monogram placeholder assumed partial photo coverage; at 0%
  // coverage it dominated the page (a wall of pastel initials), so a
  // media block now has to be earned by an actual photo.
  it('renders no media block at all when photo_url is null', () => {
    const { container } = renderRow({ photo_url: null });
    expect(screen.queryByTestId('item-photo-placeholder-item-1')).not.toBeInTheDocument();
    expect(container.querySelector('img')).toBeNull();
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

  it('makes the dish name the link into the detail page, slug + id encoded', () => {
    renderRow({});
    const link = screen.getByTestId('open-item-item-1');
    expect(link).toHaveAttribute('href', '/restaurants/cream-bean-berry/items/item-1');
    expect(link).toHaveTextContent('Pad Thai');
  });

  it('stays quiet at zero reviews instead of repeating a review CTA per card', () => {
    renderRow({});
    expect(screen.queryByText(/be the first to review/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/review/)).not.toBeInTheDocument();
  });

  it('shows a quiet review count when reviews exist, pluralized', () => {
    renderRow({ reviews_count: 1 });
    expect(screen.getByText('1 review')).toBeInTheDocument();

    renderRow({ id: 'item-2', reviews_count: 3 });
    expect(screen.getByText('3 reviews')).toBeInTheDocument();
  });
});
