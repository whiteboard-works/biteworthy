import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, within } from '@testing-library/react';

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
import type { AdminDashboardPayload, DashboardBucket } from '../../../lib/admin/metrics';

function bucket(label: string, overrides: Partial<DashboardBucket> = {}): DashboardBucket {
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

function payload(overrides: Partial<AdminDashboardPayload> = {}): AdminDashboardPayload {
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

async function spendBadgeFor(community: AdminDashboardPayload['community']) {
  mockFetchDashboard.mockResolvedValue(payload({ community }));
  const { unmount } = render(<AdminHomePage />);
  const badge = within(await screen.findByTestId('spend-card')).getByTestId('status-badge');
  const result = { tone: badge.getAttribute('data-tone'), text: badge.textContent };
  unmount();
  return result;
}

beforeEach(() => {
  mockFetchDashboard.mockReset();
});

describe('AdminHomePage', () => {
  it('renders spend vs ceiling and tiers the badge tone on the exact guard thresholds', async () => {
    mockFetchDashboard.mockResolvedValue(payload());
    render(<AdminHomePage />);
    const card = await screen.findByTestId('spend-card');
    expect(card).toHaveTextContent('$17.00');
    expect(card).toHaveTextContent('$20.00');
    const badge = within(card).getByTestId('status-badge');
    expect(badge).toHaveTextContent('85% of daily ceiling');
    expect(badge).toHaveAttribute('data-tone', 'warn');
  });

  it('is ok below 80%, warn at exactly 80%, danger at exactly the ceiling (Rails 503s at >=)', async () => {
    expect(await spendBadgeFor({ runs_today: 1, spend_today_cents: 1599, ceiling_cents: 2000 }))
      .toEqual({ tone: 'ok', text: '79% of daily ceiling' });
    expect(await spendBadgeFor({ runs_today: 1, spend_today_cents: 1600, ceiling_cents: 2000 }))
      .toEqual({ tone: 'warn', text: '80% of daily ceiling' });
    expect(await spendBadgeFor({ runs_today: 9, spend_today_cents: 2000, ceiling_cents: 2000 }))
      .toEqual({ tone: 'danger', text: 'Ceiling reached — scans paused' });
  });

  it('treats a zero ceiling as scans-paused, matching the guard (0 >= 0 → 503)', async () => {
    expect(await spendBadgeFor({ runs_today: 0, spend_today_cents: 0, ceiling_cents: 0 })).toEqual({
      tone: 'danger',
      text: 'Ceiling reached — scans paused',
    });
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

  it('recovers via the Retry button after a transient failure', async () => {
    mockFetchDashboard.mockRejectedValueOnce(new AdminError('x', 500)).mockResolvedValue(payload());
    render(<AdminHomePage />);
    expect(await screen.findByTestId('dashboard-error')).toHaveTextContent(/try again/i);

    fireEvent.click(screen.getByTestId('dashboard-retry'));

    expect(await screen.findByTestId('spend-card')).toBeInTheDocument();
    expect(screen.queryByTestId('dashboard-error')).not.toBeInTheDocument();
  });
});
