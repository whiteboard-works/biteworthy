/**
 * Phase 8.2 — TS half of the SQL ↔ TS scoring parity contract.
 *
 * The fixture at ../fixtures/taste-parity.json is ALSO loaded by
 * `apps/api/spec/services/taste_scoring_spec.rb`, which inserts the
 * same items into Postgres and asserts the SQL scores match the same
 * `expected` values to 4 decimal places. If either implementation
 * drifts, its half of this contract fails.
 */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { scoreItem, type TasteProfile } from './taste';

interface FixtureItem {
  id: string;
  name: string;
  popularity: number;
  tag_ids: string[];
  ingredient_ids: string[];
  review_ratings: number[];
  expected: Record<
    string,
    { score: number; matched_liked_tag_ids: string[]; matched_liked_ingredient_ids: string[] }
  >;
}

interface Fixture {
  profiles: Array<TasteProfile & { key: string }>;
  items: FixtureItem[];
}

const fixture: Fixture = JSON.parse(
  readFileSync(new URL('../fixtures/taste-parity.json', import.meta.url), 'utf8'),
);

const maxPopularity = Math.max(...fixture.items.map((i) => i.popularity));

const avgRating = (ratings: number[]): number | null =>
  ratings.length === 0 ? null : ratings.reduce((a, b) => a + b, 0) / ratings.length;

describe('SQL ↔ TS taste-scoring parity (shared fixture)', () => {
  for (const profile of fixture.profiles) {
    describe(`profile: ${profile.key}`, () => {
      for (const fixtureItem of fixture.items) {
        const expected = fixtureItem.expected[profile.key];
        if (!expected) continue;

        it(`scores "${fixtureItem.name}" = ${expected.score}`, () => {
          const result = scoreItem(
            {
              id: fixtureItem.id,
              name: fixtureItem.name,
              popularity: fixtureItem.popularity,
              tag_ids: fixtureItem.tag_ids,
              ingredient_ids: fixtureItem.ingredient_ids,
              avg_rating: avgRating(fixtureItem.review_ratings),
            },
            profile,
            { maxPopularity },
          );

          expect(result.score).toBeCloseTo(expected.score, 4);
          expect(result.matched_liked_tag_ids).toEqual(expected.matched_liked_tag_ids);
          expect(result.matched_liked_ingredient_ids).toEqual(
            expected.matched_liked_ingredient_ids,
          );
        });
      }
    });
  }
});
