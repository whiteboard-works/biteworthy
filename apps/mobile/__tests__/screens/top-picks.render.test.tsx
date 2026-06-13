/**
 * Phase 8.4 — mobile Top Picks row. Same contract as the web row
 * (Phase 8.3): renders only from server-provided taste_score /
 * taste_reasons via filter-engine's shared selector; anonymous
 * payloads (null scores) render nothing so the screen is unchanged.
 */
const mockPush = jest.fn();
jest.mock('expo-router', () => ({
  router: {
    push: (...args: unknown[]) => mockPush(...args),
    replace: jest.fn(),
    back: jest.fn(),
  },
  Link: 'Link',
}));

import { fireEvent, render, screen } from '@testing-library/react-native';
import { TopPicksRow } from '../../app/restaurants/_TopPicksRow';
import type { RestaurantItem } from '../../lib/api/restaurants';

const item = (overrides: Partial<RestaurantItem> & { id: string }): RestaurantItem => ({
  restaurant_id: 'rest-1',
  name: overrides.id,
  description: '',
  confidence: 'confirmed',
  popularity: 0,
  ingredient_ids: [],
  tag_ids: [],
  menu_section_id: null,
  menu_section_name: null,
  status: 'visible',
  reasons: [],
  photo_url: null,
  ...overrides,
});

const threePicks: RestaurantItem[] = [
  item({
    id: 'curry',
    name: 'Spicy Basil Curry',
    taste_score: 4,
    taste_reasons: [
      { kind: 'liked_tag', tag_id: 't1', tag_name: 'Spicy' },
      { kind: 'liked_ingredient', ingredient_id: 'i1', ingredient_name: 'Basil' },
    ],
  }),
  item({ id: 'pad', name: 'Pad Thai', taste_score: 2 }),
  item({ id: 'soup', name: 'Tom Kha Soup', taste_score: 1 }),
];

describe('TopPicksRow (mobile, Phase 8.4)', () => {
  beforeEach(() => {
    mockPush.mockClear();
  });

  it('renders cards + the "because you like…" line at ≥3 positive scores', () => {
    render(<TopPicksRow items={threePicks} />);

    expect(screen.getByText('Top picks for you')).toBeTruthy();
    expect(screen.getByTestId('pick-reason-curry').props.children).toBe(
      'Because you like Spicy & Basil',
    );
  });

  it('renders nothing below the 3-pick threshold', () => {
    render(<TopPicksRow items={threePicks.slice(0, 2)} />);
    expect(screen.queryByTestId('top-picks')).toBeNull();
  });

  it('renders nothing for an anonymous payload (null scores) — screen unchanged', () => {
    const anonymous = threePicks.map((i) => ({ ...i, taste_score: null, taste_reasons: [] }));
    render(<TopPicksRow items={anonymous} />);
    expect(screen.queryByTestId('top-picks')).toBeNull();
  });

  it('tapping a card opens the item screen', () => {
    render(<TopPicksRow items={threePicks} />);
    fireEvent.press(screen.getByLabelText('top-pick-curry'));
    expect(mockPush).toHaveBeenCalledWith('/items/curry');
  });

  it('"Why these?" toggles the taste-≠-safety explainer', () => {
    render(<TopPicksRow items={threePicks} />);

    expect(screen.queryByTestId('why-these-explainer')).toBeNull();
    fireEvent.press(screen.getByLabelText('why-these'));
    expect(screen.getByTestId('why-these-explainer').props.children).toMatch(
      /passed your dietary filter/,
    );
  });
});
