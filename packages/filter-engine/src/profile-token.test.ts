import { describe, expect, it } from 'vitest';
import {
  decodeProfileToken,
  encodeProfileToken,
  InvalidProfileTokenError,
  PROFILE_TOKEN_VERSION,
  shareableToFilterProfile,
  type ShareableProfile,
} from './profile-token';

const sample: ShareableProfile = {
  avoid_ingredient_ids: ['ing-dairy', 'ing-egg'],
  avoid_tag_ids: ['tag-contains-dairy'],
  strictness: 'balanced',
};

describe('encodeProfileToken / decodeProfileToken', () => {
  it('round-trips a typical profile', () => {
    const token = encodeProfileToken(sample);
    expect(decodeProfileToken(token)).toEqual(sample);
  });

  it('produces URL-safe characters only (no +, /, or = padding)', () => {
    // Construct a payload more likely to contain pad/+/− chars after b64.
    const wide: ShareableProfile = {
      avoid_ingredient_ids: Array.from({ length: 30 }, (_, i) => `ing-${i.toString(16).padStart(8, '0')}`),
      avoid_tag_ids: ['tag-contains-dairy'],
      strictness: 'strict',
    };
    const token = encodeProfileToken(wide);
    expect(token).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(decodeProfileToken(token)).toEqual(wide);
  });

  it('round-trips empty avoid lists', () => {
    const empty: ShareableProfile = {
      avoid_ingredient_ids: [],
      avoid_tag_ids: [],
      strictness: 'relaxed',
    };
    expect(decodeProfileToken(encodeProfileToken(empty))).toEqual(empty);
  });

  it('preserves order of ids', () => {
    const ordered: ShareableProfile = {
      avoid_ingredient_ids: ['c', 'a', 'b'],
      avoid_tag_ids: ['z', 'y'],
      strictness: 'balanced',
    };
    expect(decodeProfileToken(encodeProfileToken(ordered)).avoid_ingredient_ids).toEqual([
      'c',
      'a',
      'b',
    ]);
  });

  it('round-trips unicode-safe characters in ids (UUID stays pristine)', () => {
    const uuid: ShareableProfile = {
      avoid_ingredient_ids: ['7c1b9f0a-4e6e-44b3-9a4e-c9c2b0e5b6e1'],
      avoid_tag_ids: [],
      strictness: 'strict',
    };
    expect(decodeProfileToken(encodeProfileToken(uuid))).toEqual(uuid);
  });

  it('embeds the schema version so decoders can guard old payloads', () => {
    const token = encodeProfileToken(sample);
    // Decode the payload by hand; v should equal the constant.
    const padded = token.replace(/-/g, '+').replace(/_/g, '/');
    const padding = padded.length % 4 === 0 ? '' : '='.repeat(4 - (padded.length % 4));
    const json = Buffer.from(padded + padding, 'base64').toString('utf8');
    expect(JSON.parse(json).v).toBe(PROFILE_TOKEN_VERSION);
  });
});

describe('decodeProfileToken — error cases', () => {
  it('rejects empty string', () => {
    expect(() => decodeProfileToken('')).toThrow(InvalidProfileTokenError);
  });

  it('rejects non-base64url garbage', () => {
    expect(() => decodeProfileToken('not!base64@@@')).toThrow(InvalidProfileTokenError);
  });

  it('rejects unsupported schema versions', () => {
    const futureToken = Buffer.from(
      JSON.stringify({ v: 99, ai: [], at: [], s: 'balanced' }),
    )
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');
    expect(() => decodeProfileToken(futureToken)).toThrow(/unsupported version/);
  });

  it('rejects invalid strictness values', () => {
    const badToken = Buffer.from(JSON.stringify({ v: 1, ai: [], at: [], s: 'YOLO' }))
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');
    expect(() => decodeProfileToken(badToken)).toThrow(/s must be one of/);
  });

  it('rejects non-string ids', () => {
    const badToken = Buffer.from(JSON.stringify({ v: 1, ai: [42], at: [], s: 'balanced' }))
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');
    expect(() => decodeProfileToken(badToken)).toThrow(/ai must be string\[\]/);
  });
});

describe('shareableToFilterProfile', () => {
  it('drops prefer_tag_ids (always [] for tokenized profiles)', () => {
    const fp = shareableToFilterProfile(sample);
    expect(fp.prefer_tag_ids).toEqual([]);
    expect(fp.avoid_ingredient_ids).toEqual(sample.avoid_ingredient_ids);
    expect(fp.avoid_tag_ids).toEqual(sample.avoid_tag_ids);
    expect(fp.strictness).toBe(sample.strictness);
  });
});
