import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';

/**
 * The edit panel is where a verifier fixes what the extractor got
 * wrong before it reaches the live menu. Two rules protect data the
 * edit never meant to touch, and both are pinned here:
 *
 *   - Only CHANGED facets are sent. Payload arrays replace wholesale
 *     server-side and gap-fill keeps appending chips while the panel is
 *     open, so resending an untouched array would wipe an allergen the
 *     AI just added.
 *   - Chip rows keep their confidence/source. Those drive strict-mode
 *     trust and tell gap-fill which rows it still owns.
 */

const mockSearchIngredients = vi.fn();
const mockFetchTags = vi.fn();
vi.mock('../../../../../lib/onboarding', () => ({
  searchIngredients: (q: string) => mockSearchIngredients(q),
  fetchTags: (f: string[]) => mockFetchTags(f),
}));

import {
  ItemEditPanel,
  draftBlockers,
  draftFromItem,
  editsFromDraft,
  priceRowErrors,
} from '../_ItemEditPanel';
import type { IngestionItemPayload } from '../../../../../lib/ingestion';

const item: IngestionItemPayload = {
  id: 'i1',
  ingestion_run_id: 'r1',
  item_id: null,
  position: 0,
  name: 'Pad Thai',
  description: 'Rice noodles.',
  section_name: null,
  decision: 'pending',
  decided_at: null,
  ingredients_payload: [{ slug: 'nut-peanut', confidence: 0.97 }],
  tags_payload: [{ slug: 'cuisine-thai', confidence: 0.99 }],
  prices_payload: [{ size: null, price_cents: 1450 }],
  unresolved_ingredients: [],
  unresolved_tags: [],
};

beforeEach(() => {
  vi.useRealTimers();
  mockSearchIngredients.mockReset().mockResolvedValue([]);
  mockFetchTags.mockReset().mockResolvedValue([]);
});

describe('editsFromDraft', () => {
  it('sends nothing when nothing changed', () => {
    const baseline = draftFromItem(item);
    expect(editsFromDraft(structuredClone(baseline), baseline)).toEqual({});
  });

  // The headline guard: gap-fill appends chips while the panel is open,
  // and a resent untouched array would silently drop them.
  it('omits untouched facets so a concurrent gap-fill append survives', () => {
    const baseline = draftFromItem(item);
    const draft = structuredClone(baseline);
    draft.name = 'Pad Thai (spicy)';

    const edits = editsFromDraft(draft, baseline);

    expect(edits).toEqual({ name: 'Pad Thai (spicy)' });
    expect(edits).not.toHaveProperty('ingredients_payload');
    expect(edits).not.toHaveProperty('tags_payload');
    expect(edits).not.toHaveProperty('prices_payload');
  });

  it('keeps confidence and source on rows it did not add', () => {
    const baseline = draftFromItem(item);
    const draft = structuredClone(baseline);
    draft.ingredients = [
      ...draft.ingredients,
      { slug: 'vegetable-tofu', confidence: 1, source: 'human' },
    ];

    expect(editsFromDraft(draft, baseline).ingredients_payload).toEqual([
      { slug: 'nut-peanut', confidence: 0.97 },
      { slug: 'vegetable-tofu', confidence: 1, source: 'human' },
    ]);
  });

  it('sends an empty array when every chip is removed (an explicit clear)', () => {
    const baseline = draftFromItem(item);
    const draft = structuredClone(baseline);
    draft.ingredients = [];
    expect(editsFromDraft(draft, baseline).ingredients_payload).toEqual([]);
  });

  it('converts dollars to cents and drops unparsable rows', () => {
    const baseline = draftFromItem(item);
    const draft = structuredClone(baseline);
    draft.prices = [
      { size: 'small', price: '8.95' },
      { size: 'large', price: '' },
      { size: 'junk', price: '$12' },
    ];
    expect(editsFromDraft(draft, baseline).prices_payload).toEqual([
      { size: 'small', price_cents: 895 },
    ]);
  });

  it('rounds cents without float drift', () => {
    const baseline = draftFromItem(item);
    const draft = structuredClone(baseline);
    draft.prices = [
      { size: 'a', price: '8.95' },
      { size: 'b', price: '19.99' },
      { size: 'c', price: '0.07' },
    ];
    expect(editsFromDraft(draft, baseline).prices_payload).toEqual([
      { size: 'a', price_cents: 895 },
      { size: 'b', price_cents: 1999 },
      { size: 'c', price_cents: 7 },
    ]);
  });
});

describe('draft blockers', () => {
  it('blocks a nameless dish (it would 422 at promote)', () => {
    const draft = draftFromItem(item);
    draft.name = '   ';
    expect(draftBlockers(draft)).toMatch(/name/i);
  });

  it('flags junk prices by row instead of silently dropping them', () => {
    const draft = draftFromItem(item);
    draft.prices = [
      { size: '', price: '8.95' },
      { size: '', price: '8,95' },
      { size: '', price: '-5' },
    ];
    expect(priceRowErrors(draft)).toEqual([1, 2]);
    expect(draftBlockers(draft)).toMatch(/8\.95/);
  });

  it('allows a blank price row (a dish with no listed price)', () => {
    const draft = draftFromItem(item);
    draft.prices = [{ size: 'regular', price: '' }];
    expect(draftBlockers(draft)).toBeNull();
  });
});

describe('ItemEditPanel', () => {
  const noop = () => undefined;

  it('removes a chip through the × affordance', () => {
    const onChange = vi.fn();
    render(
      <ItemEditPanel draft={draftFromItem(item)} onChange={onChange} onCancel={noop} />,
    );

    fireEvent.click(screen.getByTestId('remove-ingredients-nut-peanut'));

    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ ingredients: [] }));
  });

  it('searches the taxonomy and adds the pick as a human-sourced row', async () => {
    mockSearchIngredients.mockResolvedValue([{ id: 'x', slug: 'vegetable-tofu', name: 'Tofu' }]);
    const onChange = vi.fn();
    render(
      <ItemEditPanel draft={draftFromItem(item)} onChange={onChange} onCancel={noop} />,
    );

    fireEvent.change(screen.getByTestId('search-ingredients'), { target: { value: 'tof' } });

    fireEvent.click(await screen.findByTestId('add-ingredients-vegetable-tofu'));
    expect(onChange).toHaveBeenCalledWith(
      expect.objectContaining({
        ingredients: [
          { slug: 'nut-peanut', confidence: 0.97 },
          { slug: 'vegetable-tofu', confidence: 1, source: 'human' },
        ],
      }),
    );
  });

  it('hides suggestions already on the dish', async () => {
    mockSearchIngredients.mockResolvedValue([
      { id: 'y', slug: 'nut-peanut', name: 'Peanut' },
      { id: 'x', slug: 'vegetable-tofu', name: 'Tofu' },
    ]);
    render(<ItemEditPanel draft={draftFromItem(item)} onChange={vi.fn()} onCancel={noop} />);

    fireEvent.change(screen.getByTestId('search-ingredients'), { target: { value: 'p' } });
    fireEvent.change(screen.getByTestId('search-ingredients'), { target: { value: 'pea' } });

    await screen.findByTestId('add-ingredients-vegetable-tofu');
    expect(screen.queryByTestId('add-ingredients-nut-peanut')).not.toBeInTheDocument();
  });

  it('debounces: one request per pause, not per keystroke', async () => {
    mockSearchIngredients.mockResolvedValue([]);
    render(<ItemEditPanel draft={draftFromItem(item)} onChange={vi.fn()} onCancel={noop} />);

    const input = screen.getByTestId('search-ingredients');
    for (const value of ['to', 'tof', 'tofu']) {
      fireEvent.change(input, { target: { value } });
    }

    await waitFor(() => expect(mockSearchIngredients).toHaveBeenCalledTimes(1));
    expect(mockSearchIngredients).toHaveBeenCalledWith('tofu');
  });

  it('does not search on a single character', () => {
    render(<ItemEditPanel draft={draftFromItem(item)} onChange={vi.fn()} onCancel={noop} />);
    fireEvent.change(screen.getByTestId('search-ingredients'), { target: { value: 't' } });
    expect(mockSearchIngredients).not.toHaveBeenCalled();
  });

  it('adds and removes price rows', () => {
    const onChange = vi.fn();
    render(<ItemEditPanel draft={draftFromItem(item)} onChange={onChange} onCancel={noop} />);

    fireEvent.click(screen.getByTestId('add-price'));
    expect(onChange).toHaveBeenLastCalledWith(
      expect.objectContaining({
        prices: [
          { size: '', price: '14.50' },
          { size: '', price: '' },
        ],
      }),
    );

    fireEvent.click(screen.getByTestId('remove-price-0'));
    expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({ prices: [] }));
  });

  it('offers a discard affordance', () => {
    const onCancel = vi.fn();
    render(<ItemEditPanel draft={draftFromItem(item)} onChange={vi.fn()} onCancel={onCancel} />);
    fireEvent.click(screen.getByTestId('cancel-edit'));
    expect(onCancel).toHaveBeenCalled();
  });

  it('warns on a matched card that edits only shape what gets added', () => {
    render(
      <ItemEditPanel draft={draftFromItem(item)} onChange={vi.fn()} onCancel={noop} matched />,
    );
    expect(screen.getByTestId('edit-append-note')).toHaveTextContent(/won’t take it off the live/i);
  });

  it('omits the append note for a plain new-dish card', () => {
    render(<ItemEditPanel draft={draftFromItem(item)} onChange={vi.fn()} onCancel={noop} />);
    expect(screen.queryByTestId('edit-append-note')).not.toBeInTheDocument();
  });
});
