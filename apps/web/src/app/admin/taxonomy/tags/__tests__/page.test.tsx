import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, within } from '@testing-library/react';

/**
 * The tags editor mirrors the ingredients page; what's distinct and
 * worth pinning: the family filter drives the fetch, create sends the
 * chosen family, and edit exposes only name/description (family is
 * fixed after create — the server 422s changes).
 */

const mockFetchList = vi.fn();
const mockCreate = vi.fn();
const mockUpdate = vi.fn();
vi.mock('../../../../../lib/admin/taxonomy', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../../lib/admin/taxonomy')>()),
  fetchAdminTags: (q: unknown) => mockFetchList(q),
  createTag: (b: unknown) => mockCreate(b),
  updateTag: (id: string, b: unknown) => mockUpdate(id, b),
}));

vi.mock('next/navigation', () => ({
  usePathname: () => '/admin/taxonomy/tags',
}));

import AdminTagsPage from '../page';

function tag(overrides: Record<string, unknown> = {}) {
  return {
    id: 't1',
    slug: 'diet-vegan',
    name: 'Vegan',
    path: 'diet_vegan',
    family: 'diet',
    description: null,
    items_count: 4,
    created_at: '2026-07-30T12:00:00Z',
    ...overrides,
  };
}

function listPayload(tags: unknown[]) {
  return { tags, pagination: { total: tags.length, limit: 100, offset: 0 } };
}

beforeEach(() => {
  mockFetchList.mockReset();
  mockCreate.mockReset();
  mockUpdate.mockReset();
});

describe('AdminTagsPage', () => {
  it('filters by family and resets paging', async () => {
    mockFetchList.mockResolvedValue(listPayload([tag()]));
    render(<AdminTagsPage />);
    await screen.findByTestId('tag-diet-vegan');

    fireEvent.change(screen.getByTestId('tag-family-filter'), { target: { value: 'cuisine' } });

    await vi.waitFor(() =>
      expect(mockFetchList).toHaveBeenLastCalledWith(
        expect.objectContaining({ family: 'cuisine', offset: 0 }),
      ),
    );
  });

  it('creates with the chosen family', async () => {
    mockFetchList.mockResolvedValue(listPayload([]));
    mockCreate.mockResolvedValue(tag({ slug: 'prep-smoked' }));
    render(<AdminTagsPage />);
    await screen.findByTestId('tag-create-form');

    fireEvent.change(screen.getByTestId('tag-new-slug'), { target: { value: 'prep-smoked' } });
    fireEvent.change(screen.getByTestId('tag-new-name'), { target: { value: 'Smoked' } });
    fireEvent.change(screen.getByTestId('tag-new-path'), { target: { value: 'prep_smoked' } });
    fireEvent.change(screen.getByTestId('tag-new-family'), { target: { value: 'prep' } });
    fireEvent.click(screen.getByTestId('tag-create'));

    await vi.waitFor(() =>
      expect(mockCreate).toHaveBeenCalledWith(
        expect.objectContaining({ slug: 'prep-smoked', family: 'prep' }),
      ),
    );
  });

  it('edit exposes only name/description and saves via the server response', async () => {
    mockFetchList.mockResolvedValue(listPayload([tag()]));
    mockUpdate.mockResolvedValue(tag({ name: 'Plant-based' }));
    render(<AdminTagsPage />);
    const row = await screen.findByTestId('tag-diet-vegan');

    fireEvent.click(within(row).getByTestId('tag-edit-diet-vegan'));
    expect(within(row).getByTestId('tag-name-diet-vegan')).toBeInTheDocument();
    // No family/slug/path inputs in the edit panel.
    expect(within(row).queryByDisplayValue('diet_vegan')).not.toBeInTheDocument();

    fireEvent.change(within(row).getByTestId('tag-name-diet-vegan'), {
      target: { value: 'Plant-based' },
    });
    fireEvent.click(within(row).getByTestId('tag-save-diet-vegan'));

    await vi.waitFor(() => expect(row).toHaveTextContent('Plant-based'));
    expect(mockUpdate).toHaveBeenCalledWith('t1', { name: 'Plant-based', description: '' });
  });
});
