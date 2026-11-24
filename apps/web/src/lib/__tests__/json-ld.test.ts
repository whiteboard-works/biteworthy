import { describe, expect, it } from 'vitest';
import { restaurantItemListJsonLd, serializeJsonLd } from '../json-ld';

/**
 * JSON-LD is inlined into HTML. A restaurant name or FAQ answer that
 * contains `<` (or a crafted `</script>`) must not break out of the
 * <script> tag — that would be an XSS hole on an indexable page.
 */
describe('serializeJsonLd', () => {
  it('escapes `<` so a `</script>` payload cannot break out of the tag', () => {
    const html = serializeJsonLd({ name: '</script><img src=x onerror=alert(1)>' });
    expect(html).not.toContain('<');
    expect(html).toContain('\\u003c');
  });

  it('round-trips through JSON.parse to the original value', () => {
    const payload = { name: '</script>', count: 2, nested: { ok: true } };
    expect(JSON.parse(serializeJsonLd(payload))).toEqual(payload);
  });
});

describe('restaurantItemListJsonLd', () => {
  it('lists restaurants as name + url only, with a trailing slash on the origin stripped', () => {
    const json = restaurantItemListJsonLd({
      restaurants: [{ name: 'Tacos', web_path: '/restaurants/usa/colorado/durango/tacos' }],
      siteUrl: 'https://bite-worthy.com/',
    });
    expect(json['@type']).toBe('ItemList');
    const items = json.itemListElement as Array<{
      item: Record<string, unknown>;
    }>;
    expect(items[0]?.item).toEqual({
      '@type': 'Restaurant',
      name: 'Tacos',
      url: 'https://bite-worthy.com/restaurants/usa/colorado/durango/tacos',
    });
    expect(items[0]?.item).not.toHaveProperty('address');
    expect(items[0]?.item).not.toHaveProperty('aggregateRating');
  });

  it('escapes `<` in a restaurant name when serialized', () => {
    const json = restaurantItemListJsonLd({
      restaurants: [{ name: 'A < B', web_path: '/restaurants/a' }],
      siteUrl: 'https://bite-worthy.com',
    });
    const html = serializeJsonLd(json);
    expect(html).not.toContain('<');
    expect(JSON.parse(html)).toEqual(json);
  });
});
