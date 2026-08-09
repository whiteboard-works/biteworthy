/**
 * Only Rails decodes a share token, so these assert the encoded bytes
 * rather than a TS round-trip: what matters is that the payload Ruby
 * will parse carries the right fields. `apps/api/spec/services/profile_token_spec.rb`
 * holds the other half — a literal token from this encoder that
 * `ProfileToken.decode` must accept and re-emit byte for byte.
 */
import { describe, expect, it } from 'vitest';
import { encodeProfileToken, PROFILE_TOKEN_VERSION, type ShareableProfile } from './profile-token';

const sample: ShareableProfile = {
  avoid_ingredient_ids: ['ing-dairy', 'ing-egg'],
  avoid_tag_ids: ['tag-contains-dairy'],
  strictness: 'balanced',
};

/** The decode half of the contract lives in Ruby; this is the test's own reader. */
function payloadOf(token: string): Record<string, unknown> {
  const padded = token.replace(/-/g, '+').replace(/_/g, '/');
  const padding = padded.length % 4 === 0 ? '' : '='.repeat(4 - (padded.length % 4));
  return JSON.parse(Buffer.from(padded + padding, 'base64').toString('utf8'));
}

describe('encodeProfileToken', () => {
  it('encodes the avoid lists and strictness under the short wire keys', () => {
    expect(payloadOf(encodeProfileToken(sample))).toMatchObject({
      v: PROFILE_TOKEN_VERSION,
      ai: ['ing-dairy', 'ing-egg'],
      at: ['tag-contains-dairy'],
      s: 'balanced',
    });
  });

  it('produces URL-safe characters only (no +, /, or = padding)', () => {
    // A payload wide enough to force pad/+ / chars out of plain base64.
    const wide: ShareableProfile = {
      avoid_ingredient_ids: Array.from(
        { length: 30 },
        (_, i) => `ing-${i.toString(16).padStart(8, '0')}`,
      ),
      avoid_tag_ids: ['tag-contains-dairy'],
      strictness: 'strict',
    };
    expect(encodeProfileToken(wide)).toMatch(/^[A-Za-z0-9_-]+$/);
  });

  it('preserves id order so the recipient sees the sharer list as written', () => {
    const ordered: ShareableProfile = {
      avoid_ingredient_ids: ['c', 'a', 'b'],
      avoid_tag_ids: ['z', 'y'],
      strictness: 'balanced',
    };
    expect(payloadOf(encodeProfileToken(ordered)).ai).toEqual(['c', 'a', 'b']);
  });

  it('round-trips empty avoid lists as empty arrays, not null', () => {
    const empty: ShareableProfile = {
      avoid_ingredient_ids: [],
      avoid_tag_ids: [],
      strictness: 'relaxed',
    };
    expect(payloadOf(encodeProfileToken(empty))).toMatchObject({ ai: [], at: [], s: 'relaxed' });
  });
});

describe('profile token expiry (legal E6)', () => {
  it('stamps a ~30-day expiry so a shared dietary profile cannot live forever', () => {
    const now = 1_000_000;
    const { exp } = payloadOf(encodeProfileToken(sample, { nowSeconds: now })) as {
      exp: number;
    };
    expect(exp).toBe(now + 30 * 24 * 60 * 60);
  });

  it('honors an explicit expiry (used by the Ruby parity fixture)', () => {
    const token = encodeProfileToken(sample, { expiresAt: 4102444800 });
    expect(payloadOf(token).exp).toBe(4102444800);
  });
});
