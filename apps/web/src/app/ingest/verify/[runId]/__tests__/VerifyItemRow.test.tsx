import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { VerifyItemRow } from '../_VerifyItemRow';
import * as ingestion from '../../../../../lib/ingestion';
import type { IngestionItemPayload } from '../../../../../lib/ingestion';

vi.mock('../../../../../lib/ingestion', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../../../../lib/ingestion')>();
  return { ...actual, decideRunItem: vi.fn() };
});

const decideMock = vi.mocked(ingestion.decideRunItem);

const item: IngestionItemPayload = {
  id: 'item-1',
  ingestion_run_id: 'run-1',
  item_id: null,
  position: 0,
  name: 'Pad Thai',
  description: 'Rice noodles, peanut, lime.',
  section_name: 'Noodles',
  decision: 'pending',
  decided_at: null,
  ingredients_payload: [{ slug: 'nut-peanut', confidence: 0.97 }],
  tags_payload: [{ slug: 'cuisine-thai', confidence: 0.99 }],
  prices_payload: [{ size: null, price_cents: 1450 }],
  addons_payload: [],
  unresolved_ingredients: [],
  unresolved_tags: [],
};

// NOTE: no beforeEach mock-clearing here — vitest 4 flags later
// rejected mock results as unhandled when the mock was cleared in a
// beforeEach (empirically verified). Per-test mockImplementation
// overrides + toHaveBeenLastCalledWith give the same isolation.
describe('VerifyItemRow', () => {
  it('renders name, price, and payload chips when enriched', () => {
    render(<VerifyItemRow runId="run-1" item={item} enriched onDecided={vi.fn()} />);

    expect(screen.getByText('Pad Thai')).toBeInTheDocument();
    expect(screen.getByText('$14.50')).toBeInTheDocument();
    expect(screen.getByText('nut-peanut')).toBeInTheDocument();
    expect(screen.getByText('cuisine-thai')).toBeInTheDocument();
  });

  it('renders add-on sub-rows with prices, and none when the dish has no add-ons', () => {
    const withAddons = {
      ...item,
      addons_payload: [
        { name: 'guajillo-tomatillo salsa', price_cents: 400, source: 'extract' as const },
        { name: 'extra peanuts', price_cents: null, source: 'guard' as const },
      ],
    };
    const { rerender } = render(
      <VerifyItemRow runId="run-1" item={withAddons} enriched onDecided={vi.fn()} />,
    );

    expect(screen.getByTestId('item-addons')).toHaveTextContent('+ guajillo-tomatillo salsa');
    expect(screen.getByTestId('item-addons')).toHaveTextContent('$4.00');
    expect(screen.getByTestId('item-addons')).toHaveTextContent('+ extra peanuts');

    rerender(<VerifyItemRow runId="run-1" item={item} enriched onDecided={vi.fn()} />);
    expect(screen.queryByTestId('item-addons')).toBeNull();
  });

  it('shows an "AI is still checking" hint on a staged, empty-payload dish while gap-fill runs', () => {
    const empty = { ...item, ingredients_payload: [], tags_payload: [] };
    render(<VerifyItemRow runId="run-1" item={empty} enriched enriching onDecided={vi.fn()} />);

    expect(screen.getByTestId('item-enriching')).toBeInTheDocument();
  });

  it('does not show the gap-fill hint once the dish has chips', () => {
    render(<VerifyItemRow runId="run-1" item={item} enriched enriching onDecided={vi.fn()} />);

    expect(screen.queryByTestId('item-enriching')).not.toBeInTheDocument();
  });

  it('shows "matching…" instead of chips while the run is still enriching', () => {
    render(<VerifyItemRow runId="run-1" item={item} enriched={false} onDecided={vi.fn()} />);

    expect(screen.getByTestId('item-matching')).toBeInTheDocument();
    expect(screen.queryByText('nut-peanut')).toBeNull();
  });

  it('accept wires through decideRunItem and reports the updated item', async () => {
    const updated = { ...item, decision: 'accepted' as const };
    decideMock.mockResolvedValue(updated);
    const onDecided = vi.fn();
    render(<VerifyItemRow runId="run-1" item={item} enriched onDecided={onDecided} />);

    fireEvent.click(screen.getByRole('button', { name: 'Accept' }));

    await waitFor(() => expect(onDecided).toHaveBeenCalledWith(updated));
    expect(decideMock).toHaveBeenLastCalledWith({
      runId: 'run-1',
      itemId: 'item-1',
      decision: 'accepted',
    });
  });

  it('decided items show a status badge + Undo (no Accept/Reject)', () => {
    render(
      <VerifyItemRow
        runId="run-1"
        item={{ ...item, decision: 'accepted' }}
        enriched
        onDecided={vi.fn()}
      />,
    );

    expect(screen.getByText('accepted')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Accept' })).toBeNull();
    expect(screen.getByTestId('undo')).toBeInTheDocument();
  });

  it('Undo reverts the decision via decideRunItem(pending)', async () => {
    const reverted = { ...item, decision: 'pending' as const };
    decideMock.mockResolvedValue(reverted);
    const onDecided = vi.fn();
    render(
      <VerifyItemRow
        runId="run-1"
        item={{ ...item, decision: 'accepted' }}
        enriched
        onDecided={onDecided}
      />,
    );

    fireEvent.click(screen.getByTestId('undo'));

    await waitFor(() => expect(onDecided).toHaveBeenCalledWith(reverted));
    expect(decideMock).toHaveBeenLastCalledWith({
      runId: 'run-1',
      itemId: 'item-1',
      decision: 'pending',
    });
  });

  it('renders the friendly error when the decision fails', async () => {
    decideMock.mockImplementation(() =>
      Promise.reject(new ingestion.IngestionRequestError(503, { error: 'cost_ceiling_reached' })),
    );
    render(<VerifyItemRow runId="run-1" item={item} enriched onDecided={vi.fn()} />);

    fireEvent.click(screen.getByRole('button', { name: 'Accept' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(/budget/);
  });
});
