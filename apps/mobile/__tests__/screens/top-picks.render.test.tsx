/**
 * Phase 8.4 — mobile Top Picks row. Same contract as the web row
 * (Phase 8.3): renders only from server-provided taste_score /
 * taste_reasons via filter-engine's shared selector. When there are
 * no picks it says why — sign in, start rating, or rate a few more —
 * matching the web row's empty states.
 */
const mockPush = jest.fn();
const mockReplace = jest.fn();
jest.mock('expo-router', () => ({
  router: {
    push: (...args: unknown[]) => mockPush(...args),
    replace: (...args: unknown[]) => mockReplace(...args),
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
    mockReplace.mockClear();
  });

  it('renders cards + the "because you like…" line at ≥3 positive scores', () => {
    render(<TopPicksRow items={threePicks} restaurantId="rest-1" signedIn />);

    expect(screen.getByText('Your best bets here')).toBeTruthy();
    expect(screen.getByTestId('pick-reason-curry').props.children).toBe(
      'Because you like Spicy & Basil',
    );
  });

  // A card without a photo beside cards with one sits shorter in the
  // strip. A same-size tile lines them up; with no photos at all the
  // cards stay compact.
  it('gives photo-less picks a placeholder only when another pick has a photo', () => {
    const withPhoto = [
      { ...threePicks[0]!, photo_url: 'https://example.com/c.jpg' },
      ...threePicks.slice(1),
    ];
    const { rerender } = render(<TopPicksRow items={withPhoto} restaurantId="rest-1" signedIn />);
    // Decorative and hidden from screen readers, so the query has to opt in.
    const hidden = { includeHiddenElements: true };
    expect(screen.getByTestId('pick-photo-placeholder-pad', hidden)).toBeTruthy();
    expect(screen.queryByTestId('pick-photo-placeholder-curry', hidden)).toBeNull();

    rerender(<TopPicksRow items={threePicks} restaurantId="rest-1" signedIn />);
    expect(screen.queryByTestId('pick-photo-placeholder-pad', hidden)).toBeNull();
  });

  it('below the 3-pick threshold, a signed-in user gets a quiet "rate a few more" nudge', () => {
    render(<TopPicksRow items={threePicks.slice(0, 2)} restaurantId="rest-1" signedIn />);
    expect(screen.queryByTestId('top-picks')).toBeNull();
    expect(screen.getByTestId('top-picks-almost')).toBeTruthy();
  });

  it('signed in with no taste signal at all: points them at rating dishes', () => {
    const unscored = threePicks.map((i) => ({ ...i, taste_score: null, taste_reasons: [] }));
    render(<TopPicksRow items={unscored} restaurantId="rest-1" signedIn />);
    expect(screen.queryByTestId('top-picks')).toBeNull();
    expect(screen.getByTestId('top-picks-no-signals')).toBeTruthy();
  });

  it('signed out: sign-in link returns to this restaurant afterwards', () => {
    const anonymous = threePicks.map((i) => ({ ...i, taste_score: null, taste_reasons: [] }));
    render(<TopPicksRow items={anonymous} restaurantId="rest-1" signedIn={false} />);
    expect(screen.queryByTestId('top-picks')).toBeNull();
    fireEvent.press(screen.getByLabelText('Sign in to see your best bets here'));
    // replace, so Back after signing in can't reveal the stale signed-out screen.
    expect(mockReplace).toHaveBeenCalledWith('/login?next=%2Frestaurants%2Frest-1');
  });

  it('tapping a card opens the item screen', () => {
    render(<TopPicksRow items={threePicks} restaurantId="rest-1" signedIn />);
    fireEvent.press(screen.getByTestId('top-pick-curry'));
    expect(mockPush).toHaveBeenCalledWith('/items/curry');
  });

  it('"Why these?" toggles the taste-≠-safety explainer', () => {
    render(<TopPicksRow items={threePicks} restaurantId="rest-1" signedIn />);

    expect(screen.queryByTestId('why-these-explainer')).toBeNull();
    fireEvent.press(screen.getByTestId('why-these'));
    expect(screen.getByTestId('why-these-explainer').props.children).toMatch(
      /passed your dietary filter/,
    );
  });
});
