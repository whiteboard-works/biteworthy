import { Suspense } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen } from '@testing-library/react';

/**
 * The admin run-detail page is where community scans become live menu
 * data. What matters: item review reuses the verify machinery (an
 * admin accept = confidence confirmed, enforced server-side), the two
 * levers are two-step confirmed, confirm-community reports exactly
 * what it flipped, and a refused re-extract explains itself instead of
 * showing a generic failure.
 */

const mockFetchRun = vi.fn();
const mockFetchRunItems = vi.fn();
const mockAcceptAll = vi.fn();
vi.mock('../../../../../lib/ingestion', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../../lib/ingestion')>()),
  fetchRun: () => mockFetchRun(),
  fetchRunItems: () => mockFetchRunItems(),
  acceptAllRunItems: () => mockAcceptAll(),
}));

const mockReExtract = vi.fn();
const mockConfirmCommunity = vi.fn();
vi.mock('../../../../../lib/admin/runs', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../../lib/admin/runs')>()),
  reExtractRun: (id: string) => mockReExtract(id),
  confirmCommunity: (id: string) => mockConfirmCommunity(id),
}));

import AdminRunPage from '../page';
import { AdminError } from '../../../../../lib/admin/shared';

function run(overrides: Record<string, unknown> = {}) {
  return {
    id: 'run-1',
    status: 'staged',
    enrichment_status: 'completed',
    input_kind: 'photo',
    restaurant_id: 'rest-1',
    state_history: {},
    failure_message: null,
    api_cost_cents: 23,
    latency_ms: 900,
    input_count: 1,
    ingestion_items_count: 1,
    created_at: '2026-07-30T12:00:00Z',
    updated_at: '2026-07-30T12:01:00Z',
    ...overrides,
  };
}

function stagedItem(overrides: Record<string, unknown> = {}) {
  return {
    id: 'ii-1',
    ingestion_run_id: 'run-1',
    item_id: null,
    position: 0,
    name: 'Carne Asada Taco',
    description: null,
    section_name: 'Tacos',
    decision: 'pending',
    decided_at: null,
    ingredients_payload: [],
    tags_payload: [],
    prices_payload: [],
    unresolved_ingredients: [],
    unresolved_tags: [],
    ...overrides,
  };
}

// `use(params)` suspends on first render, so the render must happen
// inside an awaited act for the promise to resolve before assertions.
async function renderPage() {
  await act(async () => {
    render(
      <Suspense fallback={null}>
        <AdminRunPage params={Promise.resolve({ runId: 'run-1' })} />
      </Suspense>,
    );
  });
}

beforeEach(() => {
  mockFetchRun.mockReset().mockResolvedValue(run());
  mockFetchRunItems.mockReset().mockResolvedValue([stagedItem()]);
  mockAcceptAll.mockReset();
  mockReExtract.mockReset();
  mockConfirmCommunity.mockReset();
});

describe('AdminRunPage', () => {
  it('renders the staged items through the shared verify row', async () => {
    await renderPage();
    expect(await screen.findByTestId('verify-item-ii-1')).toHaveTextContent('Carne Asada Taco');
    expect(screen.getByTestId('admin-accept-all')).toHaveTextContent('Accept all 1');
  });

  it('confirm-community requires the armed click, then reports the flipped counts', async () => {
    mockConfirmCommunity.mockResolvedValue({
      restaurant_id: 'rest-1',
      confirmed: { items: 2, ingredients: 5, tags: 1 },
    });
    await renderPage();
    await screen.findByTestId('confirm-community-panel');

    fireEvent.click(screen.getByTestId('confirm-community'));
    expect(mockConfirmCommunity).not.toHaveBeenCalled();

    fireEvent.click(screen.getByTestId('confirm-community-confirm'));
    expect(await screen.findByTestId('confirm-community-result')).toHaveTextContent(
      'Confirmed 2 item(s), 5 ingredient link(s), 1 tag link(s)',
    );
    expect(mockConfirmCommunity).toHaveBeenCalledWith('rest-1');
  });

  it('maps a refused re-extract to instructions, not a generic failure', async () => {
    mockReExtract.mockRejectedValue(new AdminError('x', 422, 'has_promoted_items'));
    await renderPage();
    await screen.findByTestId('admin-run-detail');

    fireEvent.click(await screen.findByTestId('run-re-extract'));
    fireEvent.click(screen.getByTestId('run-re-extract-confirm'));

    expect(await screen.findByTestId('run-error')).toHaveTextContent(
      'Undo the accepted items first',
    );
  });
});
