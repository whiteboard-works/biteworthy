/**
 * Phase 7.3 — the verify screen is the last leg of the scan loop:
 * pipeline progress (stage copy) → swipe deck → deep-link into the
 * user's own filtered menu. Mocks follow the ingest.render.test.tsx
 * pattern (mock-prefixed vars + arrow indirection for the hoist).
 */
const mockPush = jest.fn();
const mockReplace = jest.fn();
jest.mock('expo-router', () => ({
  router: {
    push: (...args: unknown[]) => mockPush(...args),
    replace: (...args: unknown[]) => mockReplace(...args),
    back: jest.fn(),
  },
  useLocalSearchParams: () => ({ runId: 'run-77' }),
  Link: 'Link',
}));

jest.mock('../../lib/auth', () => ({
  getJwt: jest.fn(() => Promise.resolve('jwt-1')),
}));

const mockGetRun = jest.fn();
const mockListItems = jest.fn();
const mockDecide = jest.fn();
jest.mock('../../lib/api/ingestion-runs', () => ({
  ...jest.requireActual('../../lib/api/ingestion-runs'),
  getIngestionRun: (...args: unknown[]) => mockGetRun(...args),
  listIngestionItems: (...args: unknown[]) => mockListItems(...args),
  decideIngestionItem: (...args: unknown[]) => mockDecide(...args),
}));

import { fireEvent, render, screen, waitFor } from '@testing-library/react-native';
import VerifyScreen from '../../app/ingest/verify';

const run = (status: string) => ({
  id: 'run-77',
  status,
  input_kind: 'photo',
  restaurant_id: 'rest-1',
  state_history: {},
  failure_message: null,
  api_cost_cents: 0,
  latency_ms: null,
  input_count: 1,
  ingestion_items_count: 1,
  created_at: '2026-06-12T00:00:00Z',
  updated_at: '2026-06-12T00:00:00Z',
});

const pendingItem = {
  id: 'ii-1',
  ingestion_run_id: 'run-77',
  item_id: null,
  name: 'Carnitas Taco',
  description: 'Slow-braised pork',
  section_name: 'Tacos',
  decision: 'pending',
  decided_at: null,
  ingredients_payload: [{ slug: 'pork', confidence: 0.95 }],
  tags_payload: [],
  addons_payload: [],
  unresolved_ingredients: [],
  unresolved_tags: [],
};

describe('VerifyScreen (Phase 7.3)', () => {
  beforeEach(() => {
    mockPush.mockClear();
    mockReplace.mockClear();
    mockGetRun.mockReset();
    mockListItems.mockReset();
    mockDecide.mockReset();
  });

  it('maps pipeline stages to human progress copy', async () => {
    mockGetRun.mockResolvedValue(run('extracting'));
    render(<VerifyScreen />);

    await waitFor(() => expect(screen.getByText('Reading the menu…')).toBeTruthy());
  });

  it('finishing the deck on an auto-published run celebrates and deep-links to the menu', async () => {
    // Poll sees staged; the deck-done refetch sees the 80% auto-publish.
    mockGetRun.mockResolvedValueOnce(run('staged')).mockResolvedValueOnce(run('published'));
    mockListItems.mockResolvedValue([pendingItem]);
    mockDecide.mockResolvedValue({ ...pendingItem, decision: 'accepted' });
    render(<VerifyScreen />);

    await waitFor(() => expect(screen.getByText('Carnitas Taco')).toBeTruthy());
    fireEvent.press(screen.getByLabelText('accept'));

    await waitFor(() => expect(screen.getByText('Menu published! 🎉')).toBeTruthy());
    expect(mockDecide).toHaveBeenCalledWith(
      expect.objectContaining({ runId: 'run-77', itemId: 'ii-1', decision: 'accepted' }),
    );

    fireEvent.press(screen.getByLabelText('view-menu'));
    expect(mockReplace).toHaveBeenCalledWith('/restaurants/rest-1?from=scan');
  });

  it('below the publish threshold the done screen still links to the restaurant', async () => {
    // Both the poll and the deck-done refetch see staged (< 80% accepted).
    mockGetRun.mockResolvedValue(run('staged'));
    mockListItems.mockResolvedValue([pendingItem]);
    mockDecide.mockResolvedValue({ ...pendingItem, decision: 'rejected' });
    render(<VerifyScreen />);

    await waitFor(() => expect(screen.getByText('Carnitas Taco')).toBeTruthy());
    fireEvent.press(screen.getByLabelText('reject'));

    await waitFor(() => expect(screen.getByText('All done!')).toBeTruthy());
    expect(screen.getByLabelText('view-menu')).toBeTruthy();
  });

  it('renders add-on rows on the card when the dish has them', async () => {
    mockGetRun.mockResolvedValue(run('staged'));
    mockListItems.mockResolvedValue([
      {
        ...pendingItem,
        addons_payload: [{ name: 'guajillo salsa', price_cents: 400, source: 'extract' }],
      },
    ]);
    render(<VerifyScreen />);

    await waitFor(() => expect(screen.getByText('Carnitas Taco')).toBeTruthy());
    expect(screen.getByText('Add-ons')).toBeTruthy();
    expect(screen.getByText('+ guajillo salsa $4.00')).toBeTruthy();
  });

  it('"nothing to verify" still offers the menu link', async () => {
    mockGetRun.mockResolvedValue(run('published'));
    mockListItems.mockResolvedValue([]);
    render(<VerifyScreen />);

    await waitFor(() => expect(screen.getByText('Nothing to verify')).toBeTruthy());
    fireEvent.press(screen.getByLabelText('view-menu'));
    expect(mockReplace).toHaveBeenCalledWith('/restaurants/rest-1?from=scan');
  });
});
