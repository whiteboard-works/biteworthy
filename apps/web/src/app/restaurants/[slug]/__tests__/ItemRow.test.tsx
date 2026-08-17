import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ItemRow } from '../ItemRow';
import type { RestaurantItem } from '../../../../lib/restaurants';

/**
 * Phase 4.11.4 deferred snapshot — finally landing.
 *
 * Covers the photo_url contract added in PR #169: `<img>` appears
 * with src=photo_url when the field is set; no media block renders
 * when null. Plus a few sibling tests so future ItemRow changes
 * don't drift.
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

  it('renders no media block at all when photo_url is null', () => {
    // No placeholder tile either: a media block has to be earned by a
    // real photo, so photo-less cards stay compact.
    const { container } = renderRow({ photo_url: null });
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
    // The affordance must survive touch + keyboard, where hover styles
    // don't exist — the underline has to be always-on.
    expect(link.className).toContain('underline');
  });

  it('carries the preset onto the item link so the diet survives the hop', () => {
    render(
      <ul>
        <ItemRow
          item={baseItem}
          restaurantSlug="cream-bean-berry"
          presetSlug="gluten-free"
          overridden={false}
          onToggleOverride={vi.fn()}
          onSetPersistentOverride={vi.fn()}
        />
      </ul>,
    );
    expect(screen.getByTestId('open-item-item-1')).toHaveAttribute(
      'href',
      '/restaurants/cream-bean-berry/items/item-1?profile=gluten-free',
    );
  });

  it('stays quiet at zero reviews while keeping the card entry point', () => {
    renderRow({ reviews_count: 0 });
    // reviews_count: 0 explicitly — a falsy-zero regression (rendering
    // a literal "0") must fail here, not just the undefined case.
    expect(screen.queryByText(/review/i)).not.toBeInTheDocument();
    expect(screen.queryByText('0')).not.toBeInTheDocument();
    // The dish page must stay reachable from a zero-review card.
    expect(screen.getByTestId('open-item-item-1')).toHaveAttribute(
      'href',
      '/restaurants/cream-bean-berry/items/item-1',
    );
  });

  it('links a quiet review count when one review exists', () => {
    renderRow({ reviews_count: 1 });
    const count = screen.getByText('1 review');
    expect(count.closest('a')).toHaveAttribute(
      'href',
      '/restaurants/cream-bean-berry/items/item-1',
    );
  });

  it('pluralizes the review count', () => {
    renderRow({ id: 'item-2', reviews_count: 3 });
    expect(screen.getByText('3 reviews')).toBeInTheDocument();
  });
});
