import { describe, expect, it } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { tasteReasonLine, TopPicksRow, topPicksFromScores } from '../TopPicksRow';
import type { RestaurantItem } from '../../../../lib/restaurants';

/**
 * Phase 8.3 — Top Picks row. Renders only from server-provided
 * taste_score/taste_reasons (Phase 8.2); anonymous payloads carry
 * null scores, so the row must vanish entirely — that's the
 * "anonymous unchanged" contract.
 */

const item = (overrides: Partial<RestaurantItem> & { id: string }): RestaurantItem => ({
  restaurant_id: 'rest-1',
  name: overrides.id,
  description: '',
  ingredient_ids: [],
  tag_ids: [],
  confidence: 'confirmed',
  menu_section_id: null,
  menu_section_name: null,
  status: 'visible',
  reasons: [],
  photo_url: null,
  ...overrides,
});

const scored = (id: string, taste_score: number) => item({ id, taste_score });

describe('topPicksFromScores', () => {
  it('returns [] below 3 positive-score items (no fake enthusiasm)', () => {
    expect(topPicksFromScores([scored('a', 2), scored('b', 1), scored('c', 0)])).toEqual([]);
  });

  it('returns [] when scores are null (anonymous / zero-signal payload)', () => {
    const items = [item({ id: 'a' }), item({ id: 'b' }), item({ id: 'c' })];
    expect(topPicksFromScores(items)).toEqual([]);
  });

  it('excludes hidden items even with positive scores', () => {
    const items = [
      scored('a', 3),
      scored('b', 2),
      { ...scored('hidden', 5), status: 'hidden' as const },
      scored('c', 1),
    ];
    expect(topPicksFromScores(items).map((i) => i.id)).toEqual(['a', 'b', 'c']);
  });

  it('caps at 5, sorted score desc → name asc', () => {
    const items = [
      scored('f', 1),
      scored('e', 2),
      scored('d', 3),
      scored('tie-z', 4),
      scored('tie-a', 4),
      scored('best', 5),
    ];
    expect(topPicksFromScores(items).map((i) => i.id)).toEqual([
      'best',
      'tie-a',
      'tie-z',
      'd',
      'e',
    ]);
  });
});

describe('tasteReasonLine', () => {
  it('joins tag + ingredient names into the "because you like…" line', () => {
    expect(
      tasteReasonLine([
        { kind: 'liked_tag', tag_id: 't1', tag_name: 'Spicy' },
        { kind: 'liked_ingredient', ingredient_id: 'i1', ingredient_name: 'Basil' },
      ]),
    ).toBe('Because you like Spicy & Basil');
  });

  it('handles a single name and null names', () => {
    expect(tasteReasonLine([{ kind: 'liked_tag', tag_id: 't1', tag_name: 'Spicy' }])).toBe(
      'Because you like Spicy',
    );
    expect(tasteReasonLine([{ kind: 'liked_tag', tag_id: 't1', tag_name: null }])).toBeNull();
    expect(tasteReasonLine(undefined)).toBeNull();
  });
});

describe('TopPicksRow', () => {
  const threePicks = [
    {
      ...scored('curry', 4),
      name: 'Spicy Basil Curry',
      taste_reasons: [
        { kind: 'liked_tag' as const, tag_id: 't1', tag_name: 'Spicy' },
        { kind: 'liked_ingredient' as const, ingredient_id: 'i1', ingredient_name: 'Basil' },
      ],
    },
    { ...scored('pad', 2), name: 'Pad Thai' },
    { ...scored('soup', 1), name: 'Tom Kha Soup' },
  ];

  it('renders the row with a reason line per pick at ≥3 positive scores', () => {
    render(<TopPicksRow items={threePicks} restaurantSlug="ninis" />);

    expect(screen.getByTestId('top-picks')).toBeInTheDocument();
    expect(screen.getByText('Top picks for you')).toBeInTheDocument();
    expect(screen.getByTestId('pick-reason-curry')).toHaveTextContent(
      'Because you like Spicy & Basil',
    );
  });

  it('renders nothing below the 3-pick threshold', () => {
    render(<TopPicksRow items={threePicks.slice(0, 2)} restaurantSlug="ninis" />);
    expect(screen.queryByTestId('top-picks')).not.toBeInTheDocument();
  });

  it('renders nothing for an anonymous payload (all scores null)', () => {
    const anonymous = threePicks.map(({ taste_score: _score, taste_reasons: _r, ...rest }) => ({
      ...rest,
      taste_score: null,
    }));
    render(<TopPicksRow items={anonymous} restaurantSlug="ninis" />);
    expect(screen.queryByTestId('top-picks')).not.toBeInTheDocument();
  });

  it('"Why these?" toggles the explainer (taste ≠ safety copy)', () => {
    render(<TopPicksRow items={threePicks} restaurantSlug="ninis" />);

    expect(screen.queryByTestId('why-these-explainer')).not.toBeInTheDocument();
    fireEvent.click(screen.getByTestId('why-these'));
    expect(screen.getByTestId('why-these-explainer')).toHaveTextContent(
      /passed your dietary filter/,
    );
  });

  it('links each pick to its item page', () => {
    render(<TopPicksRow items={threePicks} restaurantSlug="ninis" />);
    const link = screen.getByTestId('top-pick-curry').querySelector('a');
    expect(link).toHaveAttribute('href', '/restaurants/ninis/items/curry');
  });

  it('offers an "Improve my picks" link into the standalone taste step', () => {
    render(<TopPicksRow items={threePicks} restaurantSlug="ninis" />);
    expect(screen.getByTestId('improve-picks')).toHaveAttribute('href', '/onboarding?step=taste');
  });
});
