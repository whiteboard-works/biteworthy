import { describe, expect, it } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { RestaurantSearch } from '../_RestaurantSearch';
import type { RestaurantSummary } from '../../../lib/restaurants';

const summary = (slug: string, name: string, city = 'Durango'): RestaurantSummary => ({
  id: slug,
  slug,
  name,
  status: 'published',
  city: { slug: city.toLowerCase(), name: city, region: 'Colorado' },
  street: null,
  latitude: null,
  longitude: null,
});

const LIST = [
  summary('chamayo', 'Chamayo'),
  summary('zia-taqueria', 'Zia Taqueria'),
  summary('rgp-s-wraps', "RGP's Wraps"),
];

describe('RestaurantSearch', () => {
  it('shows the full list with no query', () => {
    render(<RestaurantSearch restaurants={LIST} />);
    expect(screen.getAllByTestId(/restaurant-card-/)).toHaveLength(3);
  });

  it('filters by name, case-insensitively', () => {
    render(<RestaurantSearch restaurants={LIST} />);
    fireEvent.change(screen.getByTestId('restaurant-search'), { target: { value: 'zia' } });
    const cards = screen.getAllByTestId(/restaurant-card-/);
    expect(cards).toHaveLength(1);
    expect(screen.getByTestId('restaurant-card-zia-taqueria')).toBeInTheDocument();
  });

  it('no-match query gets its own empty state, and Clear search restores the list', () => {
    render(<RestaurantSearch restaurants={LIST} />);
    fireEvent.change(screen.getByTestId('restaurant-search'), { target: { value: 'zzz' } });
    expect(screen.getByTestId('restaurants-empty')).toHaveTextContent(/No restaurants match/);

    fireEvent.click(screen.getByTestId('restaurants-clear-search'));
    // Controlled input: clearing must reset the box AND the list — the
    // uncontrolled defaultValue version left stale text after a clear.
    expect(screen.getByTestId('restaurant-search')).toHaveValue('');
    expect(screen.getAllByTestId(/restaurant-card-/)).toHaveLength(3);
  });

  it('keeps the add-a-menu empty state when the list itself is empty', () => {
    render(<RestaurantSearch restaurants={[]} />);
    expect(screen.getByTestId('restaurants-empty')).toHaveTextContent(/No published menus yet/);
    expect(screen.getByTestId('restaurants-empty-chat')).toBeInTheDocument();
  });
});
