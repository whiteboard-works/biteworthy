import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';

/**
 * The restaurants list is the entry point to the workbench: rows link
 * by id, the community toggle applies the community_published lens,
 * and the awaiting-graduation badge only shows when something needs
 * strict-mode review.
 */

const mockFetchList = vi.fn();
vi.mock('../../../../lib/admin/management', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../lib/admin/management')>()),
  fetchAdminRestaurants: (q: unknown) => mockFetchList(q),
}));

import AdminRestaurantsPage from '../page';

function row(overrides: Record<string, unknown> = {}) {
  return {
    id: 'r1',
    slug: 'ninis',
    name: 'Nini’s Tacos',
    status: 'published',
    city: { id: 'c1', name: 'Durango' },
    created_by_user_id: null,
    claimed_by_user_id: null,
    created_at: '2026-07-30T12:00:00Z',
    items_count: 3,
    suggested_items_count: 2,
    ...overrides,
  };
}

function payload(restaurants: unknown[]) {
  return { restaurants, pagination: { total: restaurants.length, limit: 25, offset: 0 } };
}

beforeEach(() => {
  mockFetchList.mockReset();
});

describe('AdminRestaurantsPage', () => {
  it('renders rows with the awaiting-graduation badge and links to the workbench', async () => {
    mockFetchList.mockResolvedValue(payload([row(), row({ id: 'r2', slug: 'clean', name: 'Clean Cafe', suggested_items_count: 0 })]));
    render(<AdminRestaurantsPage />);

    const needsWork = await screen.findByTestId('restaurant-row-ninis');
    expect(needsWork).toHaveTextContent('2 awaiting graduation');
    expect(needsWork.querySelector('a')).toHaveAttribute('href', '/admin/restaurants/r1');

    expect(screen.getByTestId('restaurant-row-clean')).not.toHaveTextContent('awaiting graduation');
  });

  it('community toggle applies the community_published lens and resets paging', async () => {
    mockFetchList.mockResolvedValue(payload([]));
    render(<AdminRestaurantsPage />);
    await screen.findByTestId('restaurants-empty');

    fireEvent.click(screen.getByTestId('restaurants-community-filter'));

    await vi.waitFor(() =>
      expect(mockFetchList).toHaveBeenLastCalledWith(
        expect.objectContaining({ community: true, offset: 0 }),
      ),
    );
  });
});
