import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { PageHeader } from '../PageHeader';
import type { Restaurant } from '../../../../../../../lib/restaurants';

/**
 * The header renders the owner's banner and logo only when they exist;
 * a restaurant without them must look exactly as it did before branding
 * shipped.
 */

const restaurant = (over: Partial<Restaurant>): Restaurant => ({
  id: 'r-1',
  slug: 'chamayo',
  name: 'Chamayo',
  about: null,
  phone: null,
  website: null,
  status: 'published',
  web_path: '/restaurants/usa/colorado/durango/chamayo',
  claimed_at: null,
  claimed_by_user_id: null,
  city: { id: 'c-1', slug: 'durango', name: 'Durango', region: 'Colorado' },
  time_zone: null,
  hours: [],
  logo_url: null,
  banner_url: null,
  ...over,
});

const noop = vi.fn(async () => ({ favorited: false }));

describe('PageHeader', () => {
  it('renders the banner above the kicker and the logo beside the name', () => {
    render(
      <PageHeader
        restaurant={restaurant({
          banner_url: 'https://img.test/banner.webp',
          logo_url: 'https://img.test/logo.webp',
        })}
        signedIn={false}
        onToggleFavorite={noop}
      />,
    );
    expect(screen.getByTestId('restaurant-banner')).toHaveAttribute(
      'src',
      'https://img.test/banner.webp',
    );
    expect(screen.getByTestId('restaurant-logo')).toHaveAttribute(
      'src',
      'https://img.test/logo.webp',
    );
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Chamayo');
  });

  it('renders no images for a restaurant without branding', () => {
    const { container } = render(
      <PageHeader restaurant={restaurant({})} signedIn={false} onToggleFavorite={noop} />,
    );
    expect(screen.queryByTestId('restaurant-banner')).toBeNull();
    expect(screen.queryByTestId('restaurant-logo')).toBeNull();
    expect(container.querySelector('img')).toBeNull();
  });
});
