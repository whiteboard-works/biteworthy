import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';

/**
 * Legal remediation E11 — the review author gets in-app edit + delete
 * controls; everyone else gets "Report". The API still enforces
 * ownership, so these tests assert the UI gating + that the wired
 * update/delete calls fire.
 */
const mockCreate = vi.fn();
const mockUpdate = vi.fn();
const mockDelete = vi.fn();
const mockReport = vi.fn();
vi.mock('../../../../../../../../../lib/reviews', () => ({
  createReview: (...a: unknown[]) => mockCreate(...a),
  fetchReviews: vi.fn(),
  reportReview: (...a: unknown[]) => mockReport(...a),
  updateReview: (...a: unknown[]) => mockUpdate(...a),
  deleteReview: (...a: unknown[]) => mockDelete(...a),
  ReviewError: class extends Error {},
}));
vi.mock('../../../../../../../_PostHogProvider', () => ({
  useTracker: () => ({ track: vi.fn() }),
}));
vi.mock('next/navigation', () => ({ useRouter: () => ({ replace: vi.fn() }) }));

import { ReviewsClient } from '../ReviewsClient';

const review = (over = {}) => ({
  id: 'rev-1',
  item_id: 'item-1',
  user: { id: 'user-1', handle: 'mine', display_name: 'Mine' },
  rating: 3,
  body: 'Decent.',
  photo_url: null,
  created_at: '2026-06-14T00:00:00Z',
  updated_at: '2026-06-14T00:00:00Z',
  ...over,
});

const initial = (reviews: ReturnType<typeof review>[]) => ({
  item_id: 'item-1',
  reviews,
  total: reviews.length,
});

beforeEach(() => {
  mockCreate.mockReset();
  mockUpdate.mockReset();
  mockDelete.mockReset();
  mockReport.mockReset();
});
afterEach(() => vi.clearAllMocks());

describe('ReviewsClient — owner edit/delete (E11)', () => {
  it('shows Edit/Delete on the owner’s review and Report on others’', () => {
    render(
      <ReviewsClient
        itemId="item-1"
        restaurantSlug="r"
        restaurantPath="/restaurants/usa/colorado/durango/r"
        currentUserId="user-1"
        initial={initial([
          review(),
          review({ id: 'rev-2', user: { id: 'user-2', handle: 'x', display_name: 'X' } }),
        ])}
      />,
    );
    expect(screen.getByTestId('edit-rev-1')).toBeInTheDocument();
    expect(screen.getByTestId('delete-rev-1')).toBeInTheDocument();
    // The other user's review is reportable, not editable.
    expect(screen.getByTestId('report-rev-2')).toBeInTheDocument();
    expect(screen.queryByTestId('edit-rev-2')).toBeNull();
  });

  it('signed-out users get Report, never owner controls', () => {
    render(
      <ReviewsClient
        itemId="item-1"
        restaurantSlug="r"
        restaurantPath="/restaurants/usa/colorado/durango/r"
        currentUserId={null}
        initial={initial([review()])}
      />,
    );
    expect(screen.getByTestId('report-rev-1')).toBeInTheDocument();
    expect(screen.queryByTestId('edit-rev-1')).toBeNull();
  });

  it('edits in place via updateReview and reflects the saved review', async () => {
    mockUpdate.mockResolvedValue(review({ rating: 5, body: 'Amazing now.' }));
    render(
      <ReviewsClient
        itemId="item-1"
        restaurantSlug="r"
        restaurantPath="/restaurants/usa/colorado/durango/r"
        currentUserId="user-1"
        initial={initial([review()])}
      />,
    );

    fireEvent.click(screen.getByTestId('edit-rev-1'));
    fireEvent.click(screen.getByTestId('edit-star-rev-1-5'));
    await act(async () => {
      fireEvent.click(screen.getByTestId('save-edit-rev-1'));
    });

    await waitFor(() => expect(mockUpdate).toHaveBeenCalledTimes(1));
    expect(mockUpdate.mock.calls[0]![0]).toBe('rev-1');
    expect(mockUpdate.mock.calls[0]![1]).toMatchObject({ rating: 5 });
    expect(await screen.findByText('Amazing now.')).toBeInTheDocument();
  });

  it('deletes via deleteReview after confirming and removes the card', async () => {
    mockDelete.mockResolvedValue(undefined);
    render(
      <ReviewsClient
        itemId="item-1"
        restaurantSlug="r"
        restaurantPath="/restaurants/usa/colorado/durango/r"
        currentUserId="user-1"
        initial={initial([review()])}
      />,
    );

    fireEvent.click(screen.getByTestId('delete-rev-1'));
    await act(async () => {
      fireEvent.click(screen.getByTestId('confirm-delete-rev-1'));
    });

    await waitFor(() => expect(mockDelete).toHaveBeenCalledWith('rev-1'));
    expect(screen.queryByTestId('review-rev-1')).toBeNull();
  });

  it('keeps Offer this photo as the dish photo off until the diner checks it', async () => {
    mockCreate.mockResolvedValue(review({ photo_url: 'https://example.com/r.jpg' }));
    render(
      <ReviewsClient
        itemId="item-1"
        restaurantSlug="r"
        restaurantPath="/restaurants/usa/colorado/durango/r"
        currentUserId="user-1"
        initial={initial([])}
      />,
    );

    fireEvent.click(screen.getByTestId('open-composer'));
    expect(screen.queryByTestId('offer-as-dish-photo')).not.toBeInTheDocument();

    const file = new File(['img'], 'taco.jpg', { type: 'image/jpeg' });
    fireEvent.change(screen.getByLabelText('photo'), { target: { files: [file] } });
    const offer = screen.getByTestId('offer-as-dish-photo');
    expect(offer).not.toBeChecked();

    fireEvent.click(screen.getByTestId('star-4'));
    fireEvent.click(offer);
    await act(async () => {
      fireEvent.click(screen.getByTestId('submit-review'));
    });

    await waitFor(() => expect(mockCreate).toHaveBeenCalledTimes(1));
    expect(mockCreate.mock.calls[0]![1]).toMatchObject({
      rating: 4,
      photo: file,
      offerAsDishPhoto: true,
    });
  });

  it('posts the review and shows a note when the dish-photo offer is rate-limited', async () => {
    mockCreate.mockResolvedValue({
      ...review(),
      photo_offer: { status: 'rate_limited', code: 'daily_limit' },
    });
    render(
      <ReviewsClient
        itemId="item-1"
        restaurantSlug="r"
        restaurantPath="/restaurants/usa/colorado/durango/r"
        currentUserId="user-1"
        initial={initial([])}
      />,
    );
    fireEvent.click(screen.getByTestId('open-composer'));
    const file = new File(['img'], 'taco.jpg', { type: 'image/jpeg' });
    fireEvent.change(screen.getByLabelText('photo'), { target: { files: [file] } });
    fireEvent.click(screen.getByTestId('offer-as-dish-photo'));
    fireEvent.click(screen.getByTestId('star-5'));
    await act(async () => {
      fireEvent.click(screen.getByTestId('submit-review'));
    });
    expect(await screen.findByTestId('photo-offer-note')).toHaveTextContent(/10 dish photos today/i);
    expect(screen.getByText('Decent.')).toBeInTheDocument();
  });
});
