import { Suspense } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, within } from '@testing-library/react';

/**
 * The restaurant workbench: status saves go through the form (the
 * publish/unpublish lever for the whole restaurant), the item status
 * select is the per-dish unpublish, and confirm-community reports
 * what it graduated. Confidence renders but is never editable here.
 */

const mockFetchRestaurant = vi.fn();
const mockFetchItems = vi.fn();
const mockUpdateRestaurant = vi.fn();
const mockUpdateItem = vi.fn();
vi.mock('../../../../../lib/admin/management', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../../lib/admin/management')>()),
  fetchAdminRestaurant: () => mockFetchRestaurant(),
  fetchAdminRestaurantItems: () => mockFetchItems(),
  updateAdminRestaurant: (id: string, b: unknown) => mockUpdateRestaurant(id, b),
  updateAdminItem: (id: string, b: unknown) => mockUpdateItem(id, b),
}));

const mockConfirmCommunity = vi.fn();
vi.mock('../../../../../lib/admin/runs', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../../lib/admin/runs')>()),
  confirmCommunity: (id: string) => mockConfirmCommunity(id),
}));

import AdminRestaurantPage from '../page';

function detail(overrides: Record<string, unknown> = {}) {
  return {
    id: 'r1',
    slug: 'ninis',
    name: 'Nini’s Tacos',
    status: 'published',
    city: { id: 'c1', name: 'Durango' },
    created_by_user_id: null,
    claimed_by_user_id: null,
    created_at: '2026-07-30T12:00:00Z',
    about: null,
    website: null,
    phone: null,
    claimed_at: null,
    items_by_confidence: { suggested: 2, confirmed: 3 },
    ...overrides,
  };
}

function item(overrides: Record<string, unknown> = {}) {
  return {
    id: 'i1',
    restaurant_id: 'r1',
    menu_section_id: null,
    name: 'Carne Asada',
    description: null,
    status: 'published',
    confidence: 'suggested',
    popularity: 0,
    ingredient_count: 3,
    tag_count: 1,
    variants: [{ size: null, price_cents: 450 }],
    created_at: '2026-07-30T12:00:00Z',
    ...overrides,
  };
}

async function renderPage() {
  await act(async () => {
    render(
      <Suspense fallback={null}>
        <AdminRestaurantPage params={Promise.resolve({ id: 'r1' })} />
      </Suspense>,
    );
  });
}

beforeEach(() => {
  mockFetchRestaurant.mockReset().mockResolvedValue(detail());
  mockFetchItems.mockReset().mockResolvedValue({
    items: [item()],
    pagination: { total: 1, limit: 200, offset: 0 },
  });
  mockUpdateRestaurant.mockReset();
  mockUpdateItem.mockReset();
  mockConfirmCommunity.mockReset();
});

describe('AdminRestaurantPage', () => {
  it('saves the whole form with empty optional fields as NULL, never ""', async () => {
    mockUpdateRestaurant.mockResolvedValue(detail({ status: 'closed' }));
    await renderPage();

    fireEvent.change(screen.getByTestId('restaurant-status'), { target: { value: 'closed' } });
    fireEvent.click(screen.getByTestId('restaurant-save'));

    // Exact payload: untouched empty about/website/phone must ride
    // along as null (a "" here would overwrite NULLs server-side).
    await vi.waitFor(() =>
      expect(mockUpdateRestaurant).toHaveBeenCalledWith('r1', {
        name: 'Nini\u2019s Tacos',
        about: null,
        website: null,
        phone: null,
        status: 'closed',
      }),
    );
  });

  it('removal requires the inline confirm; other transitions apply on change', async () => {
    mockUpdateItem.mockResolvedValue(item({ status: 'removed' }));
    await renderPage();
    const row = await screen.findByTestId('admin-item-i1');

    fireEvent.change(within(row).getByTestId('admin-item-status-i1'), {
      target: { value: 'removed' },
    });
    // Not yet — a stray select change must not unpublish silently.
    expect(mockUpdateItem).not.toHaveBeenCalled();

    fireEvent.click(within(row).getByTestId('admin-item-remove-confirm-i1'));

    await vi.waitFor(() => expect(mockUpdateItem).toHaveBeenCalledWith('i1', { status: 'removed' }));
    expect(row).toHaveTextContent('removed');
    // Confidence renders as a badge only — no way to edit it here.
    expect(row).toHaveTextContent('suggested');
    expect(within(row).queryByDisplayValue('suggested')).not.toBeInTheDocument();
  });

  it('cancel keeps the dish published', async () => {
    await renderPage();
    const row = await screen.findByTestId('admin-item-i1');

    fireEvent.change(within(row).getByTestId('admin-item-status-i1'), {
      target: { value: 'removed' },
    });
    fireEvent.click(within(row).getByTestId('admin-item-remove-cancel-i1'));

    expect(mockUpdateItem).not.toHaveBeenCalled();
    expect(within(row).getByTestId('admin-item-status-i1')).toHaveValue('published');
  });

  it('confirm-community requires the armed click and reports graduated counts', async () => {
    mockConfirmCommunity.mockResolvedValue({
      restaurant_id: 'r1',
      confirmed: { items: 2, ingredients: 4, tags: 1 },
    });
    await renderPage();

    fireEvent.click(screen.getByTestId('restaurant-confirm-community'));
    expect(mockConfirmCommunity).not.toHaveBeenCalled();
    fireEvent.click(screen.getByTestId('restaurant-confirm-community-confirm'));

    expect(await screen.findByTestId('restaurant-confirm-result')).toHaveTextContent(
      'Confirmed 2 item(s), 4 ingredient link(s), 1 tag link(s).',
    );
    expect(mockConfirmCommunity).toHaveBeenCalledWith('r1');
  });
});
