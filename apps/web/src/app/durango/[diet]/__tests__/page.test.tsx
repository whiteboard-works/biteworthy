import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render } from '@testing-library/react';

/**
 * WBW-203: the Durango diet landings are the indexable restaurant
 * lists. An ItemList JSON-LD that invents ratings or "safe" claims
 * would be a medical/SEO lie; one that omits the restaurants the page
 * actually renders would be invisible to crawlers. This pins the
 * payload to name + url from the ranking rows already on the page.
 */

const { mockFetchCityRanking } = vi.hoisted(() => ({
  mockFetchCityRanking: vi.fn(),
}));

vi.mock('../../../../lib/durango', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../../../lib/durango')>();
  return {
    ...actual,
    fetchCityRanking: (...args: unknown[]) => mockFetchCityRanking(...args),
  };
});

const mockNotFound = vi.fn((): never => {
  throw new Error('NEXT_NOT_FOUND');
});
vi.mock('next/navigation', () => ({
  notFound: () => mockNotFound(),
}));

import DurangoDietPage from '../page';

const ranking = {
  city: { id: 'c-1', slug: 'durango', name: 'Durango', region: 'CO' },
  profile: { id: 'p-1', slug: 'vegan', name: 'Vegan', description: null },
  restaurants: [
    {
      id: 'r-1',
      slug: 'tacos',
      name: 'Tacos',
      web_path: '/restaurants/usa/colorado/durango/tacos',
      logo_url: null,
      visible_count: 5,
      hidden_count: 2,
      total_count: 7,
    },
    {
      id: 'r-2',
      slug: 'hidden-spot',
      name: 'Hidden Spot',
      web_path: '/restaurants/usa/colorado/durango/hidden-spot',
      logo_url: null,
      visible_count: 0,
      hidden_count: 10,
      total_count: 10,
    },
  ],
};

beforeEach(() => {
  mockFetchCityRanking.mockReset().mockResolvedValue(ranking);
  mockNotFound.mockClear();
});

function parsedJsonLd(container: HTMLElement): unknown[] {
  return [...container.querySelectorAll('script[type="application/ld+json"]')].map((el) =>
    JSON.parse(el.innerHTML),
  );
}

describe('DurangoDietPage JSON-LD', () => {
  it('emits an ItemList of the restaurants shown, name and url only', async () => {
    const ui = await DurangoDietPage({ params: Promise.resolve({ diet: 'vegan' }) });
    const { container } = render(ui);

    const blocks = parsedJsonLd(container);
    const list = blocks.find(
      (
        b,
      ): b is {
        '@type': string;
        itemListElement: Array<{
          '@type': string;
          position: number;
          item: { '@type': string; name: string; url: string };
        }>;
      } =>
        typeof b === 'object' && b !== null && (b as { '@type'?: string })['@type'] === 'ItemList',
    );
    expect(list).toBeDefined();
    expect(list!.itemListElement).toHaveLength(2);

    const names = list!.itemListElement.map((el) => el.item.name);
    expect(names).toEqual(['Tacos', 'Hidden Spot']);

    for (const el of list!.itemListElement) {
      expect(el['@type']).toBe('ListItem');
      expect(el.item['@type']).toBe('Restaurant');
      expect(el.item.url).toMatch(/^https:\/\/bite-worthy\.com\/restaurants\//);
      expect(el.item).not.toHaveProperty('aggregateRating');
      expect(el.item).not.toHaveProperty('starRating');
      expect(JSON.stringify(el.item)).not.toMatch(/safe/i);
    }
  });
});
