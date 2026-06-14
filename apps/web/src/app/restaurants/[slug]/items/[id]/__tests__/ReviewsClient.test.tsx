import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';

/**
 * Legal remediation E11 — the review author gets in-app edit + delete
 * controls; everyone else gets "Report". The API still enforces
 * ownership, so these tests assert the UI gating + that the wired
 * update/delete calls fire.
 */
const mockUpdate = vi.fn();
const mockDelete = vi.fn();
const mockReport = vi.fn();
vi.mock('../../../../../../lib/reviews', () => ({
  createReview: vi.fn(),
  fetchReviews: vi.fn(),
  reportReview: (...a: unknown[]) => mockReport(...a),
  updateReview: (...a: unknown[]) => mockUpdate(...a),
  deleteReview: (...a: unknown[]) => mockDelete(...a),
  ReviewError: class extends Error {},
}));
vi.mock('../../../../_PostHogProvider', () => ({ useTracker: () => ({ track: vi.fn() }) }));
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
        currentUserId="user-1"
        initial={initial([review(), review({ id: 'rev-2', user: { id: 'user-2', handle: 'x', display_name: 'X' } })])}
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
      <ReviewsClient itemId="item-1" restaurantSlug="r" currentUserId={null} initial={initial([review()])} />,
    );
    expect(screen.getByTestId('report-rev-1')).toBeInTheDocument();
    expect(screen.queryByTestId('edit-rev-1')).toBeNull();
  });

  it('edits in place via updateReview and reflects the saved review', async () => {
    mockUpdate.mockResolvedValue(review({ rating: 5, body: 'Amazing now.' }));
    render(
      <ReviewsClient itemId="item-1" restaurantSlug="r" currentUserId="user-1" initial={initial([review()])} />,
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
      <ReviewsClient itemId="item-1" restaurantSlug="r" currentUserId="user-1" initial={initial([review()])} />,
    );

    fireEvent.click(screen.getByTestId('delete-rev-1'));
    await act(async () => {
      fireEvent.click(screen.getByTestId('confirm-delete-rev-1'));
    });

    await waitFor(() => expect(mockDelete).toHaveBeenCalledWith('rev-1'));
    expect(screen.queryByTestId('review-rev-1')).toBeNull();
  });
});
