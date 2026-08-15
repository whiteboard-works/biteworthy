import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { RestaurantCard } from '../_RestaurantCard';

/**
 * The card advertises "N safe items" for a specific diet — that claim
 * only holds if the click-through opens the menu with the same preset
 * applied. A bare /restaurants/<slug> link silently drops the diet and
 * lands the user on the unfiltered menu.
 */

const ranked = {
  id: 'r-1',
  slug: 'chamayo',
  name: 'Chamayo',
  visible_count: 28,
  hidden_count: 8,
  total_count: 36,
};

describe('RestaurantCard', () => {
  it('links to the restaurant with the diet preset applied', () => {
    render(
      <ul>
        <RestaurantCard r={ranked} dietName="Celiac" dietSlug="celiac" />
      </ul>,
    );
    expect(screen.getByTestId('restaurant-link-chamayo')).toHaveAttribute(
      'href',
      '/restaurants/chamayo?profile=celiac',
    );
  });

  it('explains an all-hidden restaurant instead of showing counts', () => {
    render(
      <ul>
        <RestaurantCard
          r={{ ...ranked, visible_count: 0, hidden_count: 36 }}
          dietName="Celiac"
          dietSlug="celiac"
        />
      </ul>,
    );
    expect(screen.getByTestId('restaurant-chamayo')).toHaveTextContent(
      /No celiac-safe items in our index yet/,
    );
  });
});
