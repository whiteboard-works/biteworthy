import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';

/**
 * The cross-restaurant suggestions queue: decided rows must leave the
 * queue (they're no longer pending) via the existing owner-queue
 * decide endpoint, and a failed decision must keep the row and show
 * the error — silently dropping a still-pending suggestion would
 * strand it un-moderated.
 */

const mockFetchAdminSuggestions = vi.fn();
vi.mock('../../../../lib/admin/suggestions', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../lib/admin/suggestions')>()),
  fetchAdminSuggestions: (q: unknown) => mockFetchAdminSuggestions(q),
}));

const mockDecide = vi.fn();
vi.mock('../../../../lib/suggestions', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../lib/suggestions')>()),
  decideSuggestion: (id: string, decision: string) => mockDecide(id, decision),
}));

import AdminSuggestionsPage from '../page';

function suggestion(id: string) {
  return {
    id,
    kind: 'rename',
    status: 'pending',
    payload: { name: 'Better Name' },
    created_at: '2026-07-30T12:00:00Z',
    resolved_at: null,
    item: { id: 'i1', name: 'Old Name', restaurant_id: 'r1' },
    submitter: { id: 'u1', handle: 'helper_1', display_name: null },
  };
}

beforeEach(() => {
  mockFetchAdminSuggestions.mockReset();
  mockDecide.mockReset();
});

describe('AdminSuggestionsPage', () => {
  it('accepting refetches the queue so the page reflects the server, not a local guess', async () => {
    mockFetchAdminSuggestions
      .mockResolvedValueOnce({
        suggestions: [suggestion('s1'), suggestion('s2')],
        pagination: { total: 2, limit: 25, offset: 0 },
      })
      .mockResolvedValueOnce({
        suggestions: [suggestion('s2')],
        pagination: { total: 1, limit: 25, offset: 0 },
      });
    mockDecide.mockResolvedValue({ id: 's1', status: 'accepted' });
    render(<AdminSuggestionsPage />);
    await screen.findByTestId('admin-suggestion-s1');

    fireEvent.click(screen.getByTestId('admin-suggestion-accept-s1'));

    await vi.waitFor(() =>
      expect(screen.queryByTestId('admin-suggestion-s1')).not.toBeInTheDocument(),
    );
    expect(screen.getByTestId('admin-suggestion-s2')).toBeInTheDocument();
    expect(mockDecide).toHaveBeenCalledWith('s1', 'accepted');
    expect(mockFetchAdminSuggestions).toHaveBeenCalledTimes(2);
  });

  it('snaps back to the first page when the current page empties but the queue does not', async () => {
    // Reaching page 2 (offset 25) that comes back empty while 5 pending
    // remain — a false "Inbox zero" here would strand them unmoderated.
    mockFetchAdminSuggestions
      .mockResolvedValueOnce({
        suggestions: Array.from({ length: 25 }, (_, i) => suggestion(`p1-${i}`)),
        pagination: { total: 30, limit: 25, offset: 0 },
      })
      .mockResolvedValueOnce({
        suggestions: [],
        pagination: { total: 5, limit: 25, offset: 25 },
      })
      .mockResolvedValueOnce({
        suggestions: [suggestion('s9')],
        pagination: { total: 5, limit: 25, offset: 0 },
      });
    render(<AdminSuggestionsPage />);
    await screen.findByTestId('admin-suggestion-p1-0');

    fireEvent.click(screen.getByTestId('admin-pagination-next'));

    expect(await screen.findByTestId('admin-suggestion-s9')).toBeInTheDocument();
    expect(screen.queryByTestId('suggestions-empty')).not.toBeInTheDocument();
    expect(mockFetchAdminSuggestions).toHaveBeenCalledTimes(3);
    expect(mockFetchAdminSuggestions).toHaveBeenLastCalledWith(
      expect.objectContaining({ offset: 0 }),
    );
  });

  it('a failed decision keeps the row and shows the error', async () => {
    mockFetchAdminSuggestions.mockResolvedValue({
      suggestions: [suggestion('s1')],
      pagination: { total: 1, limit: 25, offset: 0 },
    });
    mockDecide.mockRejectedValue(new Error('boom'));
    render(<AdminSuggestionsPage />);
    await screen.findByTestId('admin-suggestion-s1');

    fireEvent.click(screen.getByTestId('admin-suggestion-reject-s1'));

    expect(await screen.findByTestId('suggestions-error')).toBeInTheDocument();
    expect(screen.getByTestId('admin-suggestion-s1')).toBeInTheDocument();
  });

  it('renders the empty-queue state', async () => {
    mockFetchAdminSuggestions.mockResolvedValue({
      suggestions: [],
      pagination: { total: 0, limit: 25, offset: 0 },
    });
    render(<AdminSuggestionsPage />);
    expect(await screen.findByTestId('suggestions-empty')).toBeInTheDocument();
  });
});
