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
  // addons_payload deliberately absent — an older API doesn't send the field,
  // and the row must render without it (deploy-skew guard).
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

  it('renders add-on sub-rows with prices, and none when the field is absent (old API)', () => {
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

  describe('re-scan update cards', () => {
    const match: ingestion.IngestionItemMatch = {
      item_id: 'existing-1',
      score: 1.0,
      existing: {
        name: 'Pad Thai',
        description: 'Old description.',
        prices: [{ size: null, price_cents: 1250 }],
      },
      diff: {
        description: { from: 'Old description.', to: 'Rice noodles, peanut, lime.' },
        prices: {
          from: [{ size: null, price_cents: 1250 }],
          to: [{ size: null, price_cents: 1450 }],
        },
        added_ingredients: ['fruit-lime'],
        added_tags: [],
      },
      no_changes: false,
    };

    it('renders the update badge, diff, and "Accept update" for a matched item', () => {
      render(
        <VerifyItemRow runId="run-1" item={{ ...item, match }} enriched onDecided={vi.fn()} />,
      );

      expect(screen.getByTestId('match-badge')).toHaveTextContent('Updates “Pad Thai”');
      const diffBlock = screen.getByTestId('match-diff');
      expect(diffBlock).toHaveTextContent('Old description.');
      expect(diffBlock).toHaveTextContent('→ Rice noodles, peanut, lime.');
      expect(diffBlock).toHaveTextContent('$12.50');
      expect(diffBlock).toHaveTextContent('→ $14.50');
      expect(diffBlock).toHaveTextContent('+ fruit-lime');
      expect(screen.getByRole('button', { name: 'Accept update' })).toBeInTheDocument();
    });

    it('renders a no-changes badge without a diff block', () => {
      const unchanged = {
        ...match,
        diff: { description: null, prices: null, added_ingredients: [], added_tags: [] },
        no_changes: true,
      };
      render(
        <VerifyItemRow
          runId="run-1"
          item={{ ...item, match: unchanged }}
          enriched
          onDecided={vi.fn()}
        />,
      );

      expect(screen.getByTestId('match-badge')).toHaveTextContent('Already on the menu');
      expect(screen.queryByTestId('match-diff')).toBeNull();
      expect(screen.getByRole('button', { name: 'Accept' })).toBeInTheDocument();
    });

    it('renders a plain create card when the field is absent (old API)', () => {
      render(<VerifyItemRow runId="run-1" item={item} enriched onDecided={vi.fn()} />);

      expect(screen.queryByTestId('match-badge')).toBeNull();
      expect(screen.queryByTestId('match-diff')).toBeNull();
      expect(screen.getByRole('button', { name: 'Accept' })).toBeInTheDocument();
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

describe('VerifyItemRow editing', () => {
  it('Save edit sends decision: edited with only the changed facets', async () => {
    decideMock.mockResolvedValue({ ...item, decision: 'edited' });
    render(<VerifyItemRow runId="run-1" item={item} enriched onDecided={vi.fn()} />);

    fireEvent.click(screen.getByTestId('edit'));
    fireEvent.change(screen.getByTestId('edit-name'), { target: { value: 'Pad Thai (spicy)' } });
    fireEvent.change(screen.getByTestId('price-amount-0'), { target: { value: '16.00' } });
    fireEvent.click(screen.getByTestId('remove-ingredients-nut-peanut'));
    fireEvent.click(screen.getByTestId('save-edit'));

    await waitFor(() => expect(decideMock).toHaveBeenCalled());
    const call = decideMock.mock.calls.at(-1)![0];
    expect(call.decision).toBe('edited');
    expect(call.edits).toEqual({
      name: 'Pad Thai (spicy)',
      ingredients_payload: [],
      prices_payload: [{ size: null, price_cents: 1600 }],
    });
    // Untouched — tags must not ride along and clobber gap-fill's work.
    expect(call.edits).not.toHaveProperty('tags_payload');
    expect(call.edits).not.toHaveProperty('description');
  });

  it('Accept while editing carries the pending corrections', async () => {
    decideMock.mockResolvedValue({ ...item, decision: 'accepted' });
    render(<VerifyItemRow runId="run-1" item={item} enriched onDecided={vi.fn()} />);

    fireEvent.click(screen.getByTestId('edit'));
    fireEvent.change(screen.getByTestId('edit-name'), { target: { value: 'Corrected' } });
    fireEvent.click(screen.getByText('Accept'));

    await waitFor(() => expect(decideMock).toHaveBeenCalled());
    expect(decideMock).toHaveBeenLastCalledWith(
      expect.objectContaining({
        decision: 'accepted',
        edits: { name: 'Corrected' },
      }),
    );
  });

  // An untouched row must not resend payloads: gap-fill keeps appending
  // suggestions after :staged, and a stale resend would wipe them.
  it('Accept without opening the editor sends no edits at all', async () => {
    decideMock.mockResolvedValue({ ...item, decision: 'accepted' });
    render(<VerifyItemRow runId="run-1" item={item} enriched onDecided={vi.fn()} />);

    fireEvent.click(screen.getByText('Accept'));

    await waitFor(() => expect(decideMock).toHaveBeenCalled());
    expect(decideMock.mock.calls.at(-1)![0]).not.toHaveProperty('edits');
  });

  it('blocks saving a nameless dish rather than letting promote 500', () => {
    render(<VerifyItemRow runId="run-1" item={item} enriched onDecided={vi.fn()} />);

    fireEvent.click(screen.getByTestId('edit'));
    fireEvent.change(screen.getByTestId('edit-name'), { target: { value: '  ' } });

    expect(screen.getByTestId('save-edit')).toBeDisabled();
    expect(screen.getByText('Accept')).toBeDisabled();
    expect(screen.getByTestId('edit-blocker')).toBeInTheDocument();
  });

  // A saved edit isn't a decision: the dish still has to be accepted,
  // and the run's 80% publish gate still counts it as undecided.
  it('flags an edited row as still needing acceptance', () => {
    render(
      <VerifyItemRow
        runId="run-1"
        item={{ ...item, decision: 'edited' }}
        enriched
        onDecided={vi.fn()}
      />,
    );

    expect(screen.getByTestId('edited-badge')).toHaveTextContent(/still needs accepting/i);
    // Still actionable — Accept/Reject stay available.
    expect(screen.getByText('Accept')).toBeInTheDocument();
  });

  it('discarding closes the editor without deciding', () => {
    // This file deliberately doesn't clear mocks between tests (see the
    // note above), so assert on the delta rather than absolute calls.
    const before = decideMock.mock.calls.length;
    render(<VerifyItemRow runId="run-1" item={item} enriched onDecided={vi.fn()} />);

    fireEvent.click(screen.getByTestId('edit'));
    fireEvent.click(screen.getByTestId('cancel-edit'));

    expect(screen.queryByTestId('item-edit-panel')).not.toBeInTheDocument();
    expect(decideMock.mock.calls.length).toBe(before);
  });

  it('rejecting with the panel open closes it', async () => {
    decideMock.mockResolvedValue({ ...item, decision: 'rejected' });
    render(<VerifyItemRow runId="run-1" item={item} enriched onDecided={vi.fn()} />);

    fireEvent.click(screen.getByTestId('edit'));
    fireEvent.click(screen.getByText('Reject'));

    await waitFor(() =>
      expect(screen.queryByTestId('item-edit-panel')).not.toBeInTheDocument(),
    );
  });
});
