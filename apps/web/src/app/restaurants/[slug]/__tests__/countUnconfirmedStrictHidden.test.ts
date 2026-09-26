import { describe, expect, it } from 'vitest';
import { countUnconfirmedStrictHidden } from '../RestaurantClient';
import type { RestaurantItem } from '../../../../lib/restaurants';
import type { ItemSection } from '@biteworthy/filter-engine';

/**
 * The strict-mode honesty line must count ONLY items hidden solely for
 * lacking confirmed ingredients — an item also caught by an avoid list
 * is hidden for a real reason too, and folding it into "unconfirmed"
 * would overstate what confirming ingredients would actually unlock.
 */
const item = (over: Partial<RestaurantItem>): RestaurantItem => ({
  id: 'i-1',
  restaurant_id: 'r-1',
  name: 'Pad Thai',
  description: '',
  confidence: 'confirmed',
  ingredient_ids: [],
  tag_ids: [],
  menu_section_id: null,
  menu_section_name: null,
  status: 'hidden',
  reasons: [],
  photo_url: null,
  ...over,
});

const section = (
  hidden: RestaurantItem[],
  visible: RestaurantItem[] = [],
): ItemSection<RestaurantItem> => ({ id: 's-1', name: 'Entrees', visible, hidden });

describe('countUnconfirmedStrictHidden', () => {
  it('counts an item hidden only by unconfirmed_strict', () => {
    const sections = [
      section([item({ reasons: [{ kind: 'unconfirmed_strict', confidence: 'inferred' }] })]),
    ];
    expect(countUnconfirmedStrictHidden(sections)).toBe(1);
  });

  it('excludes an item also caught by an avoid-list reason — it is hidden for a real reason too', () => {
    const sections = [
      section([
        item({
          reasons: [
            { kind: 'unconfirmed_strict', confidence: 'inferred' },
            {
              kind: 'avoid_ingredient',
              ingredient_id: 'ing-1',
              ingredient_name: 'Peanuts',
              ingredient_family: 'nuts',
            },
          ],
        }),
      ]),
    ];
    expect(countUnconfirmedStrictHidden(sections)).toBe(0);
  });

  it('excludes visible items and sums across sections', () => {
    const sections = [
      section(
        [item({ id: 'a', reasons: [{ kind: 'unconfirmed_strict', confidence: 'suggested' }] })],
        [item({ id: 'visible-1', status: 'visible' })],
      ),
      section([
        item({ id: 'b', reasons: [{ kind: 'unconfirmed_strict', confidence: 'inferred' }] }),
      ]),
    ];
    expect(countUnconfirmedStrictHidden(sections)).toBe(2);
  });

  it('is zero with no sections hidden for that reason', () => {
    expect(countUnconfirmedStrictHidden([section([])])).toBe(0);
  });
});
