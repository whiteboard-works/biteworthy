/**
 * Phase 3.9 — encode shareable profile tokens.
 *
 * `/r/:slug?p=<token>` lets anyone with the URL pre-filter a menu to
 * the encoder's profile without signing in. Both web + mobile mint
 * tokens with `encodeProfileToken` and pass them through opaquely;
 * only Rails decodes, via `?profile_token=` on the items endpoint
 * (`ProfileToken.decode` → `Menus::Filter.from_token`).
 *
 * There is deliberately no TS decoder. Nothing on a client ever needs
 * to read a token back, and the encoding is pinned across languages
 * where it matters: `apps/api/spec/services/profile_token_spec.rb`
 * asserts against a byte-for-byte token literal produced by this
 * encoder, so a change here fails the Ruby suite.
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

import type { Strictness } from './index';

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
  /**
   * Ingredient and tag **ids**, as UUIDs — the values the server handed
   * back in the filter, which is where both callers already get them.
   * Rails refuses a token whose entries are not ids: the avoid lists are
   * compared by array intersection, so an id that is not an id matches
   * no dish and is indistinguishable from no filter at all, which would
   * show whoever opened the link an unfiltered menu labelled as the
   * sharer's.
   */
  avoid_ingredient_ids: string[];
  avoid_tag_ids: string[];
  strictness: Strictness;
}

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

// ─── base64url helper (works in both Node and browser) ─────────────

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
