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

const mockFetchMenus = vi.fn();
vi.mock('../../../../../lib/admin/structure', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../../lib/admin/structure')>()),
  fetchAdminMenus: () => mockFetchMenus(),
  fetchAdminPlace: () => Promise.resolve({ restaurant_id: 'r1', address: null, hours: [] }),
}));

import AdminRestaurantPage from '../page';
import { AdminError } from '../../../../../lib/admin/shared';

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
  mockFetchMenus.mockReset().mockResolvedValue({
    menus: [
      {
        id: 'm1',
        name: 'Dinner',
        position: 0,
        sections: [{ id: 's1', name: 'Tacos', position: 0, items_count: 1 }],
      },
    ],
  });
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

    await vi.waitFor(() =>
      expect(mockUpdateItem).toHaveBeenCalledWith('i1', { status: 'removed' }),
    );
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

describe('AdminRestaurantPage item deep-edit', () => {
  it('saves only the facets the admin changed', async () => {
    mockFetchItems.mockResolvedValue({
      items: [
        item({
          ingredients: [{ id: 'g1', slug: 'meat-beef', name: 'Beef' }],
          tags: [],
          modifiers: [],
          variants: [{ id: 'v1', size: null, price_cents: 450, currency: 'USD' }],
        }),
      ],
      pagination: { total: 1, limit: 50, offset: 0 },
    });
    mockUpdateItem.mockResolvedValue(item({ name: 'Carne Asada Taco' }));
    await renderPage();
    const row = await screen.findByTestId('admin-item-i1');

    fireEvent.click(within(row).getByTestId('admin-item-edit-i1'));
    fireEvent.change(within(row).getByTestId('item-name-i1'), {
      target: { value: 'Carne Asada Taco' },
    });
    fireEvent.click(within(row).getByTestId('item-save-i1'));

    await vi.waitFor(() => expect(mockUpdateItem).toHaveBeenCalled());
    // Untouched facets must not ride along — slug lists and the
    // variant/modifier arrays replace wholesale server-side.
    expect(mockUpdateItem).toHaveBeenCalledWith('i1', { name: 'Carne Asada Taco' });
  });

  it('surfaces an unknown-slug refusal as instructions', async () => {
    mockFetchItems.mockResolvedValue({
      items: [item({ ingredients: [{ id: 'g1', slug: 'meat-beef', name: 'Beef' }] })],
      pagination: { total: 1, limit: 50, offset: 0 },
    });
    mockUpdateItem.mockRejectedValue(
      new AdminError('x', 422, 'unknown_ingredient_slugs', {
        error: 'unknown_ingredient_slugs',
        slugs: ['ghost-spice'],
      }),
    );
    await renderPage();
    const row = await screen.findByTestId('admin-item-i1');

    fireEvent.click(within(row).getByTestId('admin-item-edit-i1'));
    fireEvent.click(within(row).getByTestId('remove-ingredients-i1-meat-beef'));
    fireEvent.click(within(row).getByTestId('item-save-i1'));

    expect(await within(row).findByRole('alert')).toHaveTextContent(/ghost-spice/);
  });

  /**
   * The menu tree and the item rows are separate components; this
   * flatten is the only thing connecting them. Without it the section
   * select renders empty and a dish can never be moved.
   */
  it('feeds the menu tree into the item row’s section select', async () => {
    await renderPage();
    const row = await screen.findByTestId('admin-item-i1');

    fireEvent.click(within(row).getByTestId('admin-item-edit-i1'));

    const select = await within(row).findByTestId('item-section-i1');
    expect(within(select).getByRole('option', { name: 'Dinner › Tacos' })).toHaveValue('s1');

    fireEvent.change(select, { target: { value: 's1' } });
    fireEvent.click(within(row).getByTestId('item-save-i1'));

    await vi.waitFor(() =>
      expect(mockUpdateItem).toHaveBeenCalledWith('i1', { menu_section_id: 's1' }),
    );
  });
});
