import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';

/**
 * The edit panel is where a verifier fixes what the extractor got
 * wrong before it reaches the live menu. The conversions matter more
 * than the markup: chips are stored as slugs (the filter's join keys),
 * prices are edited in dollars but sent as cents, and an unparsable
 * price row is dropped rather than promoted as $0.00 or NaN.
 */

const mockSearchIngredients = vi.fn();
const mockFetchTags = vi.fn();
vi.mock('../../../../../lib/onboarding', () => ({
  searchIngredients: (q: string) => mockSearchIngredients(q),
  fetchTags: (f: string[]) => mockFetchTags(f),
}));

import { ItemEditPanel, draftFromItem, editsFromDraft } from '../_ItemEditPanel';
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
  mockSearchIngredients.mockReset().mockResolvedValue([]);
  mockFetchTags.mockReset().mockResolvedValue([]);
});

describe('draft conversions', () => {
  it('round-trips an item through draft → edits with cents preserved', () => {
    const edits = editsFromDraft(draftFromItem(item));
    expect(edits).toEqual({
      name: 'Pad Thai',
      description: 'Rice noodles.',
      ingredients_payload: [{ slug: 'nut-peanut' }],
      tags_payload: [{ slug: 'cuisine-thai' }],
      prices_payload: [{ size: null, price_cents: 1450 }],
    });
  });

  it('drops price rows without a parsable amount instead of sending NaN', () => {
    const draft = draftFromItem(item);
    draft.prices = [
      { size: 'small', price: '8.95' },
      { size: 'large', price: '' },
      { size: 'weird', price: 'free' },
    ];
    expect(editsFromDraft(draft).prices_payload).toEqual([{ size: 'small', price_cents: 895 }]);
  });

  it('sends an empty payload array when every chip is removed (clears server-side)', () => {
    const draft = draftFromItem(item);
    draft.ingredientSlugs = [];
    expect(editsFromDraft(draft).ingredients_payload).toEqual([]);
  });
});

describe('ItemEditPanel', () => {
  it('removes a chip through the × affordance', () => {
    const onChange = vi.fn();
    render(<ItemEditPanel draft={draftFromItem(item)} onChange={onChange} />);

    fireEvent.click(screen.getByTestId('remove-ingredients-nut-peanut'));

    expect(onChange).toHaveBeenCalledWith(expect.objectContaining({ ingredientSlugs: [] }));
  });

  it('searches the taxonomy and adds the picked slug', async () => {
    mockSearchIngredients.mockResolvedValue([
      { id: 'x', slug: 'vegetable-tofu', name: 'Tofu' },
      { id: 'y', slug: 'nut-peanut', name: 'Peanut' }, // already on the item
    ]);
    const onChange = vi.fn();
    render(<ItemEditPanel draft={draftFromItem(item)} onChange={onChange} />);

    fireEvent.change(screen.getByTestId('search-ingredients'), { target: { value: 'tof' } });

    const option = await screen.findByTestId('add-ingredients-vegetable-tofu');
    // Slugs already on the item are filtered out of the suggestions.
    expect(screen.queryByTestId('add-ingredients-nut-peanut')).not.toBeInTheDocument();

    fireEvent.click(option);
    expect(onChange).toHaveBeenCalledWith(
      expect.objectContaining({ ingredientSlugs: ['nut-peanut', 'vegetable-tofu'] }),
    );
  });

  it('does not search on a single character', () => {
    render(<ItemEditPanel draft={draftFromItem(item)} onChange={vi.fn()} />);
    fireEvent.change(screen.getByTestId('search-ingredients'), { target: { value: 't' } });
    expect(mockSearchIngredients).not.toHaveBeenCalled();
  });

  it('adds and removes price rows', () => {
    const onChange = vi.fn();
    render(<ItemEditPanel draft={draftFromItem(item)} onChange={onChange} />);

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

  it('warns on a matched card that edits only shape what gets added', () => {
    render(<ItemEditPanel draft={draftFromItem(item)} onChange={vi.fn()} matched />);
    expect(screen.getByTestId('edit-append-note')).toHaveTextContent(/won’t take it off the live/i);
  });

  it('omits the append note for a plain new-dish card', () => {
    render(<ItemEditPanel draft={draftFromItem(item)} onChange={vi.fn()} />);
    expect(screen.queryByTestId('edit-append-note')).not.toBeInTheDocument();
  });
});
