import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, within } from '@testing-library/react';

/**
 * Review moderation must default to the flagged queue (the actual
 * inbox), send the picked reason on hide, restore on unhide, and swap
 * rows to the server-returned state — a wrong optimistic state here
 * misrepresents what the review's author is seeing.
 */

const mockFetch = vi.fn();
const mockHide = vi.fn();
const mockUnhide = vi.fn();
vi.mock('../../../../lib/admin/reviews', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../lib/admin/reviews')>()),
  fetchModerationReviews: (q: unknown) => mockFetch(q),
  hideReview: (id: string, reason: string) => mockHide(id, reason),
  unhideReview: (id: string) => mockUnhide(id),
}));

import AdminReviewsPage from '../page';

function reviewRow(overrides: Record<string, unknown> = {}) {
  return {
    id: 'rev-1',
    rating: 4,
    body: 'Solid taco.',
    photo_url: null,
    created_at: '2026-07-30T12:00:00Z',
    flagged_at: '2026-07-30T13:00:00Z',
    hidden_at: null,
    hidden_reason: null,
    user: { id: 'u1', handle: 'diner_1', display_name: null },
    item: { id: 'i1', name: 'Carne Asada', restaurant: { id: 'r1', name: 'Nini’s', slug: 'ninis' } },
    ...overrides,
  };
}

function payload(reviews: unknown[]) {
  return { reviews, pagination: { total: reviews.length, limit: 25, offset: 0 } };
}

beforeEach(() => {
  mockFetch.mockReset();
  mockHide.mockReset();
  mockUnhide.mockReset();
});

describe('AdminReviewsPage', () => {
  it('loads the flagged queue by default and switches visibility on tab click', async () => {
    mockFetch.mockResolvedValue(payload([reviewRow()]));
    render(<AdminReviewsPage />);
    await screen.findByTestId('review-mod-rev-1');

    expect(mockFetch).toHaveBeenCalledWith(expect.objectContaining({ visibility: 'flagged' }));

    fireEvent.click(screen.getByTestId('reviews-visibility-hidden'));
    expect(mockFetch).toHaveBeenLastCalledWith(
      expect.objectContaining({ visibility: 'hidden', offset: 0 }),
    );
  });

  it('hides with the picked reason and swaps the row to the server state', async () => {
    mockFetch.mockResolvedValue(payload([reviewRow()]));
    mockHide.mockResolvedValue(
      reviewRow({ hidden_at: '2026-07-30T14:00:00Z', hidden_reason: 'off_topic', flagged_at: null }),
    );
    render(<AdminReviewsPage />);
    const row = await screen.findByTestId('review-mod-rev-1');

    fireEvent.change(within(row).getByTestId('review-reason-rev-1'), {
      target: { value: 'off_topic' },
    });
    fireEvent.click(within(row).getByTestId('review-hide-rev-1'));

    expect(await within(row).findByTestId('review-unhide-rev-1')).toBeInTheDocument();
    expect(mockHide).toHaveBeenCalledWith('rev-1', 'off_topic');
    expect(row).toHaveTextContent('hidden: off_topic');
  });

  it('unhide restores the row to moderation state', async () => {
    mockFetch.mockResolvedValue(
      payload([reviewRow({ hidden_at: '2026-07-30T14:00:00Z', hidden_reason: 'spam' })]),
    );
    mockUnhide.mockResolvedValue(reviewRow({ hidden_at: null, hidden_reason: null, flagged_at: null }));
    render(<AdminReviewsPage />);
    const row = await screen.findByTestId('review-mod-rev-1');

    fireEvent.click(within(row).getByTestId('review-unhide-rev-1'));

    expect(await within(row).findByTestId('review-hide-rev-1')).toBeInTheDocument();
    expect(mockUnhide).toHaveBeenCalledWith('rev-1');
  });

  it('surfaces fetch failures inline', async () => {
    mockFetch.mockRejectedValue(new Error('boom'));
    render(<AdminReviewsPage />);
    expect(await screen.findByTestId('reviews-error')).toBeInTheDocument();
  });
});
