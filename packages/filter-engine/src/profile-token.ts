/**
 * Phase 3.9 — encode/decode shareable profile tokens.
 *
 * `/r/:slug?p=<token>` lets anyone with the URL pre-filter a menu to
 * the encoder's profile without signing in. Both web + mobile build
 * tokens using `encodeProfileToken`; Rails reads them via
 * `?profile_token=` on the items endpoint and decodes the same
 * format. The Ruby side has its own implementation (mirrored byte-
 * for-byte by the spec) so this module is the canonical contract.
 *
 * Token shape: base64url of JSON `{ v: 2, ai, at, s, exp }`. Short keys
 * keep URLs reasonable; the `v` lets us evolve the schema later
 * without breaking old links.
 *
 * Legal remediation E6 — v2 adds `exp` (a Unix-seconds expiry). A
 * shared link carries the sharer's avoid-lists + strictness (dietary
 * data), so it must not live forever; decoders reject an expired token.
 * v1 tokens (no expiry) are intentionally no longer accepted.
 *
 * Note on signing: these tokens are minted client-side (the Share
 * button), so an HMAC secret would have to ship in the browser bundle
 * and could be forged — signing here would be theater. The token grants
 * no privilege (it only carries the sharer's own filter), so tamper-
 * resistance has no security value; strict structural validation +
 * expiry are the real protections. True signing would require minting
 * the token server-side, a larger change deferred for now.
 */

import type { FilterProfile, Strictness } from './index';

export const PROFILE_TOKEN_VERSION = 2;

/** Default lifetime of a shared link: 30 days (in seconds). */
export const PROFILE_TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60;

interface TokenPayload {
  v: number;
  ai: string[];
  at: string[];
  s: Strictness;
  exp: number;
}

export interface EncodeProfileTokenOptions {
  /** Absolute expiry, Unix seconds. Overrides the default TTL (tests/parity). */
  expiresAt?: number;
  /** "Now" in Unix seconds. Defaults to the real clock (tests). */
  nowSeconds?: number;
}

export interface ShareableProfile {
  avoid_ingredient_ids: string[];
  avoid_tag_ids: string[];
  strictness: Strictness;
}

export class InvalidProfileTokenError extends Error {
  constructor(reason: string) {
    super(`Invalid profile token: ${reason}`);
    this.name = 'InvalidProfileTokenError';
  }
}

const STRICTNESSES: ReadonlyArray<Strictness> = ['relaxed', 'balanced', 'strict'];

export function encodeProfileToken(
  profile: ShareableProfile,
  opts: EncodeProfileTokenOptions = {},
): string {
  const now = opts.nowSeconds ?? Math.floor(Date.now() / 1000);
  const exp = opts.expiresAt ?? now + PROFILE_TOKEN_TTL_SECONDS;
  const payload: TokenPayload = {
    v: PROFILE_TOKEN_VERSION,
    ai: profile.avoid_ingredient_ids,
    at: profile.avoid_tag_ids,
    s: profile.strictness,
    exp,
  };
  return base64UrlEncode(JSON.stringify(payload));
}

export function decodeProfileToken(
  token: string,
  opts: { nowSeconds?: number } = {},
): ShareableProfile {
  if (typeof token !== 'string' || token.length === 0) {
    throw new InvalidProfileTokenError('empty');
  }
  let json: string;
  try {
    json = base64UrlDecode(token);
  } catch {
    throw new InvalidProfileTokenError('not base64url');
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch {
    throw new InvalidProfileTokenError('not JSON');
  }
  if (!parsed || typeof parsed !== 'object') {
    throw new InvalidProfileTokenError('not an object');
  }
  const obj = parsed as Record<string, unknown>;
  if (obj.v !== PROFILE_TOKEN_VERSION) {
    throw new InvalidProfileTokenError(`unsupported version: ${String(obj.v)}`);
  }
  const ai = obj.ai;
  const at = obj.at;
  const s = obj.s;
  if (!Array.isArray(ai) || !ai.every((x): x is string => typeof x === 'string')) {
    throw new InvalidProfileTokenError('ai must be string[]');
  }
  if (!Array.isArray(at) || !at.every((x): x is string => typeof x === 'string')) {
    throw new InvalidProfileTokenError('at must be string[]');
  }
  if (typeof s !== 'string' || !STRICTNESSES.includes(s as Strictness)) {
    throw new InvalidProfileTokenError(`s must be one of ${STRICTNESSES.join('|')}`);
  }
  const exp = obj.exp;
  if (typeof exp !== 'number' || !Number.isFinite(exp)) {
    throw new InvalidProfileTokenError('exp must be a number');
  }
  const now = opts.nowSeconds ?? Math.floor(Date.now() / 1000);
  if (exp <= now) {
    throw new InvalidProfileTokenError('expired');
  }
  return {
    avoid_ingredient_ids: ai,
    avoid_tag_ids: at,
    strictness: s as Strictness,
  };
}

/**
 * Adapter: shareable profile -> the FilterProfile shape `applyProfile`
 * consumes. Drops `prefer_tag_ids` (always [] for tokenized profiles
 * — sharing rankings doesn't carry meaning between users).
 */
export function shareableToFilterProfile(s: ShareableProfile): FilterProfile {
  return {
    avoid_ingredient_ids: s.avoid_ingredient_ids,
    avoid_tag_ids: s.avoid_tag_ids,
    prefer_tag_ids: [],
    strictness: s.strictness,
  };
}

// ─── base64url helpers (work in both Node and browser) ─────────────

function base64UrlEncode(input: string): string {
  const bytes = utf8Encode(input);
  let b64: string;
  if (typeof Buffer !== 'undefined' && typeof Buffer.from === 'function') {
    b64 = Buffer.from(bytes).toString('base64');
  } else {
    let binary = '';
    for (const byte of bytes) binary += String.fromCharCode(byte);
    b64 = btoa(binary);
  }
  return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlDecode(input: string): string {
  const padded = input.replace(/-/g, '+').replace(/_/g, '/');
  const padding = padded.length % 4 === 0 ? '' : '='.repeat(4 - (padded.length % 4));
  const b64 = padded + padding;
  let bytes: Uint8Array;
  if (typeof Buffer !== 'undefined' && typeof Buffer.from === 'function') {
    bytes = new Uint8Array(Buffer.from(b64, 'base64'));
  } else {
    const binary = atob(b64);
    bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  }
  return utf8Decode(bytes);
}

function utf8Encode(s: string): Uint8Array {
  if (typeof TextEncoder !== 'undefined') return new TextEncoder().encode(s);
  // Fallback (very old runtimes — Node < 11). Should never hit in practice.
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x80) out.push(c);
    else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    else out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
  }
  return new Uint8Array(out);
}

function utf8Decode(bytes: Uint8Array): string {
  if (typeof TextDecoder !== 'undefined') return new TextDecoder().decode(bytes);
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]!);
  return s;
}
