import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';

/**
 * The admin deep-edit panel is how a dish that already reached the
 * menu gets corrected. Same discipline as the verify-flow editor:
 * only CHANGED facets travel (slug lists and the variant/modifier
 * arrays replace wholesale server-side, so resending an untouched one
 * would rewrite someone else's work), prices are typed in dollars and
 * sent as cents, and a nameless dish or junk price blocks the save
 * rather than reaching the API.
 */

vi.mock('../../../../../lib/onboarding', () => ({
  searchIngredients: vi.fn().mockResolvedValue([]),
  fetchTags: vi.fn().mockResolvedValue([]),
}));

import {
  ItemDeepEditPanel,
  draftBlockers,
  draftFromItem,
  editsFromDraft,
} from '../_ItemDeepEditPanel';
import type { AdminItemRow } from '../../../../../lib/admin/management';

const item = {
  id: 'i1',
  restaurant_id: 'r1',
  menu_section_id: null,
  name: 'Carne Asada',
  description: 'Grilled steak.',
  status: 'published',
  confidence: 'suggested',
  popularity: 0,
  ingredient_count: 1,
  tag_count: 1,
  ingredients: [{ id: 'ing1', slug: 'meat-beef', name: 'Beef' }],
  tags: [{ id: 't1', slug: 'cuisine-mexican', name: 'Mexican', family: 'cuisine' }],
  modifiers: [{ id: 'm1', name: 'Add avocado', kind: 'addition', price_cents: 200 }],
  variants: [{ id: 'v1', size: null, price_cents: 450, currency: 'USD' }],
  created_at: '2026-07-31T00:00:00Z',
} as unknown as AdminItemRow;

const sections = [{ id: 's1', name: 'Tacos', menuName: 'Dinner' }];

beforeEach(() => {
  vi.clearAllMocks();
});

describe('editsFromDraft', () => {
  it('sends nothing when nothing changed', () => {
    const baseline = draftFromItem(item);
    expect(editsFromDraft(structuredClone(baseline), baseline)).toEqual({});
  });

  it('omits untouched facets so a concurrent edit is not overwritten', () => {
    const baseline = draftFromItem(item);
    const draft = structuredClone(baseline);
    draft.name = 'Carne Asada Taco';

    const edits = editsFromDraft(draft, baseline);

    expect(edits).toEqual({ name: 'Carne Asada Taco' });
    expect(edits).not.toHaveProperty('ingredient_slugs');
    expect(edits).not.toHaveProperty('variants');
    expect(edits).not.toHaveProperty('modifiers');
  });

  it('sends slug lists for chip changes and cents for prices', () => {
    const baseline = draftFromItem(item);
    const draft = structuredClone(baseline);
    draft.ingredientSlugs = ['meat-beef', 'vegetable-onion'];
    draft.variants = [{ size: 'large', price: '9.75' }];

    const edits = editsFromDraft(draft, baseline);

    expect(edits.ingredient_slugs).toEqual(['meat-beef', 'vegetable-onion']);
    expect(edits.variants).toEqual([{ size: 'large', price_cents: 975 }]);
  });

  it('clears a facet with an explicit empty array', () => {
    const baseline = draftFromItem(item);
    const draft = structuredClone(baseline);
    draft.tagSlugs = [];
    draft.modifiers = [];

    const edits = editsFromDraft(draft, baseline);

    expect(edits.tag_slugs).toEqual([]);
    expect(edits.modifiers).toEqual([]);
  });

  it('sends null to unset the section and an id to move it', () => {
    const baseline = draftFromItem({ ...item, menu_section_id: 's1' } as AdminItemRow);
    const cleared = structuredClone(baseline);
    cleared.sectionId = '';
    expect(editsFromDraft(cleared, baseline).menu_section_id).toBeNull();

    const moved = structuredClone(draftFromItem(item));
    moved.sectionId = 's1';
    expect(editsFromDraft(moved, draftFromItem(item)).menu_section_id).toBe('s1');
  });

  it('keeps a priceless modifier as null rather than dropping it', () => {
    const baseline = draftFromItem(item);
    const draft = structuredClone(baseline);
    draft.modifiers = [{ name: 'Side salad', kind: 'side', price: '' }];

    expect(editsFromDraft(draft, baseline).modifiers).toEqual([
      { name: 'Side salad', kind: 'side', price_cents: null },
    ]);
  });
});

describe('draftBlockers', () => {
  it('blocks a nameless dish, a junk price, and a nameless modifier', () => {
    const nameless = draftFromItem(item);
    nameless.name = '  ';
    expect(draftBlockers(nameless)).toMatch(/name/i);

    const badPrice = draftFromItem(item);
    badPrice.variants = [{ size: '', price: '8,95' }];
    expect(draftBlockers(badPrice)).toMatch(/8\.95/);

    const badModifier = draftFromItem(item);
    badModifier.modifiers = [{ name: ' ', kind: 'addition', price: '' }];
    expect(draftBlockers(badModifier)).toMatch(/modifier/i);
  });

  it('passes a clean draft', () => {
    expect(draftBlockers(draftFromItem(item))).toBeNull();
  });
});

describe('ItemDeepEditPanel', () => {
  const noop = () => undefined;

  function renderPanel(overrides: Record<string, unknown> = {}) {
    const props = {
      itemId: 'i1',
      draft: draftFromItem(item),
      sections,
      busy: false,
      onChange: vi.fn(),
      onCancel: vi.fn(),
      onSave: vi.fn(),
      ...overrides,
    };
    render(<ItemDeepEditPanel {...(props as never)} />);
    return props;
  }

  it('renders existing chips, prices, modifiers and the section select', () => {
    renderPanel();

    expect(screen.getByTestId('remove-ingredients-i1-meat-beef')).toBeInTheDocument();
    expect(screen.getByTestId('remove-tags-i1-cuisine-mexican')).toBeInTheDocument();
    expect(screen.getByTestId('item-variant-price-i1-0')).toHaveValue('4.50');
    expect(screen.getByTestId('item-modifier-name-i1-0')).toHaveValue('Add avocado');
    expect(screen.getByTestId('item-section-i1')).toBeInTheDocument();
  });

  it('removing a chip reports the shorter slug list', () => {
    const props = renderPanel();
    fireEvent.click(screen.getByTestId('remove-ingredients-i1-meat-beef'));
    expect(props.onChange).toHaveBeenCalledWith(
      expect.objectContaining({ ingredientSlugs: [] }),
    );
  });

  it('disables Save while a blocker stands', () => {
    const blocked = draftFromItem(item);
    blocked.name = '';
    renderPanel({ draft: blocked });

    expect(screen.getByTestId('item-save-i1')).toBeDisabled();
    expect(screen.getByTestId('item-blocker-i1')).toBeInTheDocument();
  });

  it('offers discard and save affordances', () => {
    const props = renderPanel();

    fireEvent.click(screen.getByTestId('item-save-i1'));
    expect(props.onSave).toHaveBeenCalled();

    fireEvent.click(screen.getByTestId('item-cancel-i1'));
    expect(props.onCancel).toHaveBeenCalled();
  });

  it('hides the section select when the restaurant has no sections', () => {
    renderPanel({ sections: [] });
    expect(screen.queryByTestId('item-section-i1')).not.toBeInTheDocument();
  });
});
