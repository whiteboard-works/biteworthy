import { describe, expect, it, vi } from 'vitest';
import { brandRestaurant, fetchCities } from '../cities';
import { NotSignedInError } from '../chat';

/**
 * fetchCities runs on the Next server without a cache; without the
 * forwarded visitor headers every visitor would share one Rails rate-limit
 * bucket and the add-a-restaurant form would go empty under load.
 */
describe('fetchCities', () => {
  it('forwards the edge headers to Rails', async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(new Response(JSON.stringify({ cities: [] }), { status: 200 }));

    await fetchCities({ fetchImpl, edgeHeaders: { 'X-BW-Client-IP': '203.0.113.9' } });

    const init = fetchImpl.mock.calls[0]![1] as RequestInit;
    expect((init.headers as Record<string, string>)['X-BW-Client-IP']).toBe('203.0.113.9');
  });
});

/**
 * brandRestaurant is the add-a-restaurant form's only way to attach the
 * images it held; the field names are the API's contract and a lapsed
 * session must be told apart from a refused image.
 */
describe('brandRestaurant', () => {
  it('PATCHes only the images given, under the API field names', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }));
    const logo = new File(['x'], 'logo.png', { type: 'image/png' });

    await brandRestaurant('red-iguana', { logo }, fetchImpl);

    const [url, init] = fetchImpl.mock.calls[0]! as [string, RequestInit];
    expect(url).toBe('/api/restaurants/red-iguana/branding');
    expect(init.method).toBe('PATCH');
    const body = init.body as FormData;
    expect(body.get('logo')).toBe(logo);
    expect(body.has('banner')).toBe(false);
  });

  it('throws NotSignedInError on 401 and the API message otherwise', async () => {
    await expect(
      brandRestaurant(
        'x',
        { logo: null },
        vi.fn().mockResolvedValue(new Response('', { status: 401 })),
      ),
    ).rejects.toBeInstanceOf(NotSignedInError);
    await expect(
      brandRestaurant(
        'x',
        { logo: null },
        vi
          .fn()
          .mockResolvedValue(
            new Response(JSON.stringify({ error: 'not an image' }), { status: 422 }),
          ),
      ),
    ).rejects.toThrow('not an image');
  });
});
