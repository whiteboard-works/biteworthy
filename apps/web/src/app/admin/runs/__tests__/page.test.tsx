import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';

/**
 * The runs queue is the moderation inbox. What matters: the community
 * filter defaults ON (admin-scanned runs rarely need review), filter
 * state round-trips through the URL (moderators share deep links, and
 * a filter change resets paging), and rows carry enough context to
 * triage (who scanned what, decision progress, failures).
 */

const mockReplace = vi.fn();
let searchParams = new URLSearchParams();
vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: mockReplace }),
  useSearchParams: () => searchParams,
}));

const mockFetchAdminRuns = vi.fn();
vi.mock('../../../../lib/admin/runs', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../lib/admin/runs')>()),
  fetchAdminRuns: (q: unknown) => mockFetchAdminRuns(q),
}));

import AdminRunsPage from '../page';

function runRow(overrides: Record<string, unknown> = {}) {
  return {
    id: 'run-1',
    status: 'staged',
    enrichment_status: 'completed',
    input_kind: 'photo',
    failure_message: null,
    api_cost_cents: 23,
    created_at: '2026-07-30T12:00:00Z',
    user: { id: 'u-1', handle: 'scanner_1', email: 'scan@example.com', is_admin: false },
    restaurant: { id: 'rest-1', name: 'Nini’s Tacos', slug: 'ninis', status: 'published' },
    decision_counts: { pending: 3, accepted: 2, rejected: 1, edited: 0 },
    ...overrides,
  };
}

beforeEach(() => {
  mockReplace.mockReset();
  mockFetchAdminRuns.mockReset();
  searchParams = new URLSearchParams();
});

describe('AdminRunsPage', () => {
  it('fetches community-only by default and renders triage context per row', async () => {
    mockFetchAdminRuns.mockResolvedValue({
      runs: [runRow()],
      pagination: { total: 1, limit: 25, offset: 0 },
    });
    render(<AdminRunsPage />);

    const row = await screen.findByTestId('run-row-run-1');
    expect(row).toHaveTextContent('Nini’s Tacos');
    expect(row).toHaveTextContent('by scanner_1 (scan@example.com)');
    expect(row).toHaveTextContent('3 pending · 2 accepted · 1 rejected');
    // Read-only now: the per-run verify deck is gone, so rows link nowhere.
    expect(row.querySelector('a')).toBeNull();

    expect(mockFetchAdminRuns).toHaveBeenCalledWith(
      expect.objectContaining({ community: true, offset: 0 }),
    );
    expect(screen.getByTestId('runs-community-filter')).toBeChecked();
  });

  it('writes filter changes to the URL and resets paging', async () => {
    searchParams = new URLSearchParams('offset=50');
    mockFetchAdminRuns.mockResolvedValue({
      runs: [],
      pagination: { total: 0, limit: 25, offset: 50 },
    });
    render(<AdminRunsPage />);
    await screen.findByTestId('runs-past-end');

    fireEvent.change(screen.getByTestId('runs-status-filter'), { target: { value: 'staged' } });
    expect(mockReplace).toHaveBeenCalledWith('/admin/runs?status=staged');
  });

  it('offers a way back when a stale offset deep link lands past the end', async () => {
    searchParams = new URLSearchParams('offset=50');
    mockFetchAdminRuns.mockResolvedValue({
      runs: [],
      pagination: { total: 3, limit: 25, offset: 50 },
    });
    render(<AdminRunsPage />);

    fireEvent.click(await screen.findByTestId('runs-back-to-start'));
    expect(mockReplace).toHaveBeenCalledWith('/admin/runs');
  });

  it('honors community=false from a shared deep link', async () => {
    searchParams = new URLSearchParams('community=false');
    mockFetchAdminRuns.mockResolvedValue({
      runs: [],
      pagination: { total: 0, limit: 25, offset: 0 },
    });
    render(<AdminRunsPage />);
    await screen.findByTestId('runs-empty');

    expect(mockFetchAdminRuns).toHaveBeenCalledWith(expect.objectContaining({ community: false }));
    expect(screen.getByTestId('runs-community-filter')).not.toBeChecked();
  });

  it('surfaces fetch failures inline', async () => {
    mockFetchAdminRuns.mockRejectedValue(new Error('boom'));
    render(<AdminRunsPage />);
    expect(await screen.findByTestId('runs-error')).toBeInTheDocument();
  });
});
