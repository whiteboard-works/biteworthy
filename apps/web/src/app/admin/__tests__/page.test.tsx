import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, within } from '@testing-library/react';

/**
 * The ops dashboard exists to answer three questions at a glance:
 * is community spend inside the daily ceiling (the same number the
 * 503 guard enforces), is cost-per-item on target, and is anything
 * waiting in a moderation queue. These tests pin the headline paths:
 * the warn badge at ≥80% of ceiling, the over-target flag, the null
 * latency fallback (no runs yet), and the friendly error copy.
 */

const mockFetchDashboard = vi.fn();
vi.mock('../../../lib/admin/metrics', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../lib/admin/metrics')>()),
  fetchDashboard: () => mockFetchDashboard(),
}));

import AdminHomePage from '../page';
import { AdminError } from '../../../lib/admin/shared';

function bucket(label: string, overrides: Record<string, unknown> = {}) {
  return {
    label,
    run_count: 4,
    item_count: 80,
    total_cost_cents: 120,
    cost_per_item_cents: 0.4,
    avg_latency_ms: 1800,
    p95_latency_ms: 4200,
    cache_hit_rate: 0.85,
    ...overrides,
  };
}

function payload(overrides: Record<string, unknown> = {}) {
  return {
    target_cents_per_item: 0.5,
    periods: {
      today: bucket('Today', { avg_latency_ms: null, p95_latency_ms: null, run_count: 0 }),
      last_7_days: bucket('Last 7 days', { cost_per_item_cents: 0.9 }),
      last_30_days: bucket('Last 30 days'),
    },
    community: { runs_today: 3, spend_today_cents: 1700, ceiling_cents: 2000 },
    queues: {
      flagged_reviews: 2,
      pending_suggestions: 5,
      community_published_restaurants: 1,
      staged_runs: 4,
    },
    ...overrides,
  };
}

beforeEach(() => {
  mockFetchDashboard.mockReset();
});

describe('AdminHomePage', () => {
  it('renders spend vs ceiling with a warn badge at ≥80%', async () => {
    mockFetchDashboard.mockResolvedValue(payload());
    render(<AdminHomePage />);

    const card = await screen.findByTestId('spend-card');
    expect(card).toHaveTextContent('$17.00');
    expect(card).toHaveTextContent('$20.00');
    expect(within(card).getByTestId('status-badge')).toHaveTextContent('85% of daily ceiling');
  });

  it('flags the ceiling-reached state distinctly (scans are 503ing)', async () => {
    mockFetchDashboard.mockResolvedValue(
      payload({ community: { runs_today: 9, spend_today_cents: 2100, ceiling_cents: 2000 } }),
    );
    render(<AdminHomePage />);
    const card = await screen.findByTestId('spend-card');
    expect(within(card).getByTestId('status-badge')).toHaveTextContent(
      'Ceiling reached — scans paused',
    );
  });

  it('marks a period over the cost-per-item target and dashes out missing latency', async () => {
    mockFetchDashboard.mockResolvedValue(payload());
    render(<AdminHomePage />);

    const week = await screen.findByTestId('period-last_7_days');
    expect(within(week).getByTestId('status-badge')).toHaveTextContent('Over cost target');

    const today = screen.getByTestId('period-today');
    expect(within(today).queryByTestId('status-badge')).not.toBeInTheDocument();
    expect(today).toHaveTextContent('—');
  });

  it('renders every moderation queue count', async () => {
    mockFetchDashboard.mockResolvedValue(payload());
    render(<AdminHomePage />);
    expect(await screen.findByTestId('queue-flagged_reviews')).toHaveTextContent('2');
    expect(screen.getByTestId('queue-pending_suggestions')).toHaveTextContent('5');
    expect(screen.getByTestId('queue-community_published_restaurants')).toHaveTextContent('1');
    expect(screen.getByTestId('queue-staged_runs')).toHaveTextContent('4');
  });

  it('shows the friendly access-lost copy on a 404 (mid-session demotion)', async () => {
    mockFetchDashboard.mockRejectedValue(new AdminError('x', 404));
    render(<AdminHomePage />);
    expect(await screen.findByTestId('dashboard-error')).toHaveTextContent(/access is gone/i);
  });
});
