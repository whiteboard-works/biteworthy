import { buildShareUrl } from '../../lib/share-url';

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

  // Only Rails decodes the token, so read the payload here rather than
  // round-tripping through a TS decoder that no app code would run.
  it('embeds the filter in the token Rails will decode', () => {
    const url = buildShareUrl('rest', filter, 'https://x.example');
    const token = url.split('?p=')[1]!;
    const padded = token.replace(/-/g, '+').replace(/_/g, '/');
    const padding = padded.length % 4 === 0 ? '' : '='.repeat(4 - (padded.length % 4));
    const payload = JSON.parse(Buffer.from(padded + padding, 'base64').toString('utf8'));
    expect(payload).toMatchObject({
      ai: filter.avoid_ingredient_ids,
      at: filter.avoid_tag_ids,
      s: filter.strictness,
    });
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
