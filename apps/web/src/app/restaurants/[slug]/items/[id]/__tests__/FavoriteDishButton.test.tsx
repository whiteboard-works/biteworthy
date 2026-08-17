import { describe, expect, it, vi, afterEach } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import FavoriteDishButton from '../_FavoriteDishButton';

// The dish page is a server component, so the save button must live
// behind a client boundary that takes only serializable props — passing
// an onToggle function from the page 500'd every signed-in view. This
// pins the wrapper's contract: itemId in, favorite fetch out.
describe('FavoriteDishButton', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('saves the dish through the favorite proxy for its itemId', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ item_id: 'dish-1', favorited: true }),
    });
    vi.stubGlobal('fetch', fetchMock);

    render(<FavoriteDishButton itemId="dish-1" initialFavorited={false} />);

    const btn = screen.getByTestId('favorite-dish');
    expect(btn).toHaveTextContent('Save this dish');
    fireEvent.click(btn);

    await waitFor(() => expect(btn).toHaveAttribute('aria-pressed', 'true'));
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/items/dish-1/favorite',
      expect.objectContaining({ method: 'POST' }),
    );
    expect(btn).toHaveTextContent('Saved');
  });
});
