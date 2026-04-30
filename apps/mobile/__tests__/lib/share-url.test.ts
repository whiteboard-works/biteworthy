import { buildShareUrl } from '../../lib/share-url';
import { decodeProfileToken } from '@biteworthy/filter-engine';

const filter = {
  avoid_ingredient_ids: ['ing-dairy', 'ing-egg'],
  avoid_tag_ids: ['tag-contains-dairy'],
  strictness: 'balanced' as const,
};

describe('buildShareUrl', () => {
  it('encodes the slug + token into a /r/<slug>?p=<token> URL', () => {
    const url = buildShareUrl('cream-bean-berry-1', filter, 'https://biteworthy.example');
    expect(url.startsWith('https://biteworthy.example/r/cream-bean-berry-1?p=')).toBe(true);
  });

  it('produces a token that decodes back to the same filter', () => {
    const url = buildShareUrl('rest', filter, 'https://x.example');
    const token = url.split('?p=')[1]!;
    const decoded = decodeProfileToken(token);
    expect(decoded).toEqual(filter);
  });

  it('URL-encodes slugs that contain reserved characters', () => {
    const url = buildShareUrl('café & co', filter, 'https://x.example');
    expect(url).toContain('caf%C3%A9%20%26%20co');
  });

  it('falls back to the default web base when none is provided', () => {
    const url = buildShareUrl('rest', filter);
    // Default is localhost or whatever EXPO_PUBLIC_WEB_BASE evaluated to
    // at module load — assert on shape, not exact host.
    expect(url).toMatch(/^https?:\/\/.+\/r\/rest\?p=[A-Za-z0-9_-]+$/);
  });
});
