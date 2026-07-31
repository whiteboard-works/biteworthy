import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, within } from '@testing-library/react';

/**
 * The menu manager is where a scan's single bucket becomes a real menu
 * structure. The property worth guarding in the UI, because it's the
 * one an admin will hesitate over: deleting never destroys dishes.
 * The confirm copy says so, and the result reports how many dishes
 * were kept.
 */

const mockFetchMenus = vi.fn();
const mockCreateMenu = vi.fn();
const mockCreateSection = vi.fn();
const mockDeleteSection = vi.fn();
const mockDeleteMenu = vi.fn();
const mockUpdateSection = vi.fn();
vi.mock('../../../../../lib/admin/structure', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../../lib/admin/structure')>()),
  fetchAdminMenus: (id: string) => mockFetchMenus(id),
  createMenu: (id: string, body: unknown) => mockCreateMenu(id, body),
  createSection: (id: string, body: unknown) => mockCreateSection(id, body),
  deleteSection: (id: string) => mockDeleteSection(id),
  deleteMenu: (id: string) => mockDeleteMenu(id),
  updateSection: (id: string, body: unknown) => mockUpdateSection(id, body),
}));

import { MenuManager } from '../_MenuManager';

const tree = {
  menus: [
    {
      id: 'm1',
      name: 'Dinner',
      description: null,
      position: 0,
      sections: [
        { id: 's1', name: 'Tacos', description: null, position: 0, items_count: 3 },
      ],
    },
  ],
};

beforeEach(() => {
  mockFetchMenus.mockReset().mockResolvedValue(tree);
  mockCreateMenu.mockReset().mockResolvedValue({});
  mockCreateSection.mockReset().mockResolvedValue({});
  mockDeleteSection.mockReset().mockResolvedValue(3);
  mockDeleteMenu.mockReset().mockResolvedValue(undefined);
  mockUpdateSection.mockReset().mockResolvedValue({});
});

describe('MenuManager', () => {
  it('renders the tree with per-section dish counts', async () => {
    render(<MenuManager restaurantId="r1" />);

    expect(await screen.findByTestId('menu-m1')).toBeInTheDocument();
    expect(screen.getByTestId('section-s1')).toHaveTextContent('3 dishes');
  });

  it('reports dishes as kept, not deleted, when a section goes', async () => {
    render(<MenuManager restaurantId="r1" />);
    const section = await screen.findByTestId('section-s1');

    fireEvent.click(within(section).getByTestId('section-delete-s1'));
    // Two-step: the first click only arms it.
    expect(mockDeleteSection).not.toHaveBeenCalled();
    fireEvent.click(within(section).getByTestId('section-delete-s1-confirm'));

    expect(await screen.findByTestId('menus-notice')).toHaveTextContent(
      '3 dishes kept, now unsectioned',
    );
    expect(mockDeleteSection).toHaveBeenCalledWith('s1');
  });

  it('adds a menu', async () => {
    render(<MenuManager restaurantId="r1" />);
    await screen.findByTestId('menu-m1');

    fireEvent.change(screen.getByTestId('menu-new'), { target: { value: 'Brunch' } });
    fireEvent.click(screen.getByTestId('menu-add'));

    await vi.waitFor(() => expect(mockCreateMenu).toHaveBeenCalledWith('r1', { name: 'Brunch' }));
  });

  it('adds a section to a menu', async () => {
    render(<MenuManager restaurantId="r1" />);
    await screen.findByTestId('menu-m1');

    fireEvent.change(screen.getByTestId('section-new-m1'), { target: { value: 'Sides' } });
    fireEvent.click(screen.getByTestId('section-add-m1'));

    await vi.waitFor(() => expect(mockCreateSection).toHaveBeenCalledWith('m1', { name: 'Sides' }));
  });

  it('publishes the flattened section list to the parent', async () => {
    const onTreeChanged = vi.fn();
    render(<MenuManager restaurantId="r1" onTreeChanged={onTreeChanged} />);

    await screen.findByTestId('menu-m1');
    expect(onTreeChanged).toHaveBeenCalledWith(tree.menus);
  });

  it('renames a section on blur, and ignores an unchanged value', async () => {
    render(<MenuManager restaurantId="r1" />);
    const input = await screen.findByTestId('section-name-s1');

    fireEvent.blur(input, { target: { value: 'Tacos' } });
    expect(mockUpdateSection).not.toHaveBeenCalled();

    fireEvent.blur(input, { target: { value: 'Street Tacos' } });
    await vi.waitFor(() =>
      expect(mockUpdateSection).toHaveBeenCalledWith('s1', { name: 'Street Tacos' }),
    );
  });
});
