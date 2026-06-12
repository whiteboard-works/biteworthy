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
  name: 'Pad Thai',
  description: 'Rice noodles, peanut, lime.',
  section_name: 'Noodles',
  decision: 'pending',
  decided_at: null,
  ingredients_payload: [{ slug: 'nut-peanut', confidence: 0.97 }],
  tags_payload: [{ slug: 'cuisine-thai', confidence: 0.99 }],
  prices_payload: [{ size: null, price_cents: 1450 }],
  unresolved_ingredients: [],
  unresolved_tags: [],
};

// NOTE: no beforeEach mock-clearing here — vitest 4 flags later
// rejected mock results as unhandled when the mock was cleared in a
// beforeEach (empirically verified). Per-test mockImplementation
// overrides + toHaveBeenLastCalledWith give the same isolation.
describe('VerifyItemRow', () => {

  it('renders name, price, section, and payload chips', () => {
    render(<VerifyItemRow runId="run-1" item={item} onDecided={vi.fn()} />);

    expect(screen.getByText('Pad Thai')).toBeInTheDocument();
    expect(screen.getByText('$14.50')).toBeInTheDocument();
    expect(screen.getByText('Noodles')).toBeInTheDocument();
    expect(screen.getByText('nut-peanut')).toBeInTheDocument();
    expect(screen.getByText('cuisine-thai')).toBeInTheDocument();
  });

  it('accept wires through decideRunItem and reports the updated item', async () => {
    const updated = { ...item, decision: 'accepted' as const };
    decideMock.mockResolvedValue(updated);
    const onDecided = vi.fn();
    render(<VerifyItemRow runId="run-1" item={item} onDecided={onDecided} />);

    fireEvent.click(screen.getByRole('button', { name: 'Accept' }));

    await waitFor(() => expect(onDecided).toHaveBeenCalledWith(updated));
    expect(decideMock).toHaveBeenLastCalledWith({
      runId: 'run-1',
      itemId: 'item-1',
      decision: 'accepted',
    });
  });

  it('decided items show a status badge instead of buttons', () => {
    render(
      <VerifyItemRow
        runId="run-1"
        item={{ ...item, decision: 'accepted' }}
        onDecided={vi.fn()}
      />,
    );

    expect(screen.getByText('accepted')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Accept' })).toBeNull();
  });

  it('renders the friendly error when the decision fails', async () => {
    decideMock.mockImplementation(() =>
      Promise.reject(new ingestion.IngestionRequestError(503, { error: 'cost_ceiling_reached' })),
    );
    render(<VerifyItemRow runId="run-1" item={item} onDecided={vi.fn()} />);

    fireEvent.click(screen.getByRole('button', { name: 'Accept' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(/budget/);
  });
});
