import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { RestaurantCards } from '../_RestaurantCards';
import type { RestaurantSummary } from '../../lib/restaurants';

/**
 * A logo is an owner's branding, not a requirement: most restaurants
 * have none, and their cards must look exactly as before — no empty
 * image slot, no broken-image icon.
 */

const summary = (slug: string, logo_url: string | null): RestaurantSummary => ({
  id: slug,
  slug,
  name: slug,
  status: 'published',
  web_path: `/restaurants/usa/colorado/durango/${slug}`,
  city: { slug: 'durango', name: 'Durango', region: 'Colorado' },
  street: null,
  latitude: null,
  longitude: null,
  time_zone: null,
  hours: [],
  logo_url,
});

describe('RestaurantCards', () => {
  it('shows the logo beside the name when the owner set one', () => {
    render(<RestaurantCards restaurants={[summary('ninis', 'https://img.test/ninis.webp')]} />);
    const logo = screen.getByTestId('restaurant-logo-ninis');
    expect(logo).toHaveAttribute('src', 'https://img.test/ninis.webp');
    // Decorative: the name next to it is the accessible label.
    expect(logo).toHaveAttribute('alt', '');
  });

  it('renders no image at all for a restaurant without a logo', () => {
    render(<RestaurantCards restaurants={[summary('chimayo', null)]} />);
    expect(screen.queryByTestId('restaurant-logo-chimayo')).toBeNull();
    expect(screen.getByTestId('restaurant-card-chimayo').querySelector('img')).toBeNull();
  });
});
