import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import FavoriteButton from '../_FavoriteButton';

describe('FavoriteButton', () => {
  const labels = { savedLabel: 'Saved', unsavedLabel: 'Save' };

  it('renders the unsaved state and toggles to saved on click', async () => {
    const onToggle = vi.fn().mockResolvedValue({ favorited: true });
    render(<FavoriteButton initialFavorited={false} onToggle={onToggle} {...labels} testId="fav" />);

    const btn = screen.getByTestId('fav');
    expect(btn).toHaveAttribute('aria-pressed', 'false');
    expect(btn).toHaveTextContent('Save');

    fireEvent.click(btn);
    expect(onToggle).toHaveBeenCalledWith(true);
    await waitFor(() => expect(btn).toHaveAttribute('aria-pressed', 'true'));
    expect(btn).toHaveTextContent('Saved');
  });

  it('reverts the optimistic flip when the toggle fails', async () => {
    const onToggle = vi.fn().mockRejectedValue(new Error('boom'));
    render(<FavoriteButton initialFavorited={false} onToggle={onToggle} {...labels} testId="fav" />);

    const btn = screen.getByTestId('fav');
    fireEvent.click(btn);
    // Optimistically pressed, then reverts to false after the rejection.
    await waitFor(() => expect(btn).toHaveAttribute('aria-pressed', 'false'));
    expect(screen.getByText(/could not save/i)).toBeInTheDocument();
  });
});
