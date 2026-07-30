import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, within } from '@testing-library/react';

/**
 * The taxonomy editor's contract: create feeds the form through with
 * aliases split, edit exposes ONLY the mutable fields (no slug/path
 * inputs — the server refuses them), a refused delete explains what
 * still references the node instead of a generic failure, and a
 * successful delete refreshes from the server.
 */

const mockFetchList = vi.fn();
const mockCreate = vi.fn();
const mockUpdate = vi.fn();
const mockDelete = vi.fn();
vi.mock('../../../../../lib/admin/taxonomy', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../../lib/admin/taxonomy')>()),
  fetchAdminIngredients: (q: unknown) => mockFetchList(q),
  createIngredient: (b: unknown) => mockCreate(b),
  updateIngredient: (id: string, b: unknown) => mockUpdate(id, b),
  deleteIngredient: (id: string) => mockDelete(id),
}));

vi.mock('next/navigation', () => ({
  usePathname: () => '/admin/taxonomy/ingredients',
}));

import AdminIngredientsPage from '../page';
import { AdminError } from '../../../../../lib/admin/shared';

function node(overrides: Record<string, unknown> = {}) {
  return {
    id: 'i1',
    slug: 'dairy-milk',
    name: 'Milk',
    path: 'dairy.milk',
    aliases: ['whole milk'],
    allergen: true,
    items_count: 2,
    created_at: '2026-07-30T12:00:00Z',
    ...overrides,
  };
}

function listPayload(ingredients: unknown[]) {
  return { ingredients, pagination: { total: ingredients.length, limit: 100, offset: 0 } };
}

beforeEach(() => {
  mockFetchList.mockReset();
  mockCreate.mockReset();
  mockUpdate.mockReset();
  mockDelete.mockReset();
});

describe('AdminIngredientsPage', () => {
  it('creates a node from the form (aliases split) then refreshes the list', async () => {
    mockFetchList
      .mockResolvedValueOnce(listPayload([]))
      .mockResolvedValueOnce(listPayload([node({ slug: 'dairy-kefir', name: 'Kefir' })]));
    mockCreate.mockResolvedValue(node({ slug: 'dairy-kefir' }));
    render(<AdminIngredientsPage />);
    await screen.findByTestId('ingredient-create-form');

    fireEvent.change(screen.getByTestId('ingredient-new-slug'), { target: { value: 'dairy-kefir' } });
    fireEvent.change(screen.getByTestId('ingredient-new-name'), { target: { value: 'Kefir' } });
    fireEvent.change(screen.getByTestId('ingredient-new-path'), { target: { value: 'dairy.kefir' } });
    fireEvent.change(screen.getByTestId('ingredient-new-aliases'), {
      target: { value: 'kephir, milk kefir' },
    });
    fireEvent.click(screen.getByTestId('ingredient-create'));

    expect(await screen.findByTestId('ingredient-dairy-kefir')).toBeInTheDocument();
    expect(mockCreate).toHaveBeenCalledWith({
      slug: 'dairy-kefir',
      name: 'Kefir',
      path: 'dairy.kefir',
      aliases: ['kephir', 'milk kefir'],
      allergen: false,
    });
  });

  it('edit exposes only mutable fields and saves through the server response', async () => {
    mockFetchList.mockResolvedValue(listPayload([node()]));
    mockUpdate.mockResolvedValue(node({ name: 'Whole Milk' }));
    render(<AdminIngredientsPage />);
    const row = await screen.findByTestId('ingredient-dairy-milk');

    fireEvent.click(within(row).getByTestId('ingredient-edit-dairy-milk'));
    // Mutable fields only — no slug/path inputs exist in the row.
    expect(within(row).getByTestId('ingredient-name-dairy-milk')).toBeInTheDocument();
    expect(within(row).queryByDisplayValue('dairy.milk')).not.toBeInTheDocument();
    expect(within(row).queryByDisplayValue('dairy-milk')).not.toBeInTheDocument();

    fireEvent.change(within(row).getByTestId('ingredient-name-dairy-milk'), {
      target: { value: 'Whole Milk' },
    });
    fireEvent.click(within(row).getByTestId('ingredient-save-dairy-milk'));

    await vi.waitFor(() => expect(row).toHaveTextContent('Whole Milk'));
    expect(mockUpdate).toHaveBeenCalledWith('i1', {
      name: 'Whole Milk',
      aliases: ['whole milk'],
      allergen: true,
    });
  });

  it('a refused delete lists what still references the node', async () => {
    mockFetchList.mockResolvedValue(listPayload([node()]));
    mockDelete.mockRejectedValue(
      new AdminError('x', 409, 'in_use', {
        error: 'in_use',
        references: { descendants: 1, items: 2, presets: 0, modifiers: 0, profiles: 0 },
      }),
    );
    render(<AdminIngredientsPage />);
    const row = await screen.findByTestId('ingredient-dairy-milk');

    fireEvent.click(within(row).getByTestId('ingredient-delete-dairy-milk'));
    fireEvent.click(within(row).getByTestId('ingredient-delete-dairy-milk-confirm'));

    expect(await within(row).findByRole('alert')).toHaveTextContent(
      'Still referenced — 1 descendants, 2 items',
    );
    expect(row).toBeInTheDocument();
  });
});
