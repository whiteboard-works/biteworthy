/**
 * The calver format, defined once. `bump.mjs` (the writer) and
 * `src/index.test.ts` (the validator) both import from here, so a
 * scheme change is one edit — a writer emitting what the validator
 * rejects can't happen by drift.
 */

/** `YYYY.M.D` or `YYYY.M.D.X`, month/day/bump non-padded. */
export const VERSION_RE = /^(\d{4})\.([1-9]\d?)\.([1-9]\d?)(?:\.([1-9]\d*))?$/;

/**
 * [year, month, day, bump] — bare versions are bump 0.
 * Returns null for anything the scheme doesn't allow.
 */
export function parseVersion(version) {
  const m = VERSION_RE.exec(version);
  if (!m) return null;
  return [Number(m[1]), Number(m[2]), Number(m[3]), m[4] ? Number(m[4]) : 0];
}

/** Positive when a is newer than b; 0 when equal; negative when older. */
export function compareVersions(a, b) {
  const pa = parseVersion(a);
  const pb = parseVersion(b);
  if (!pa || !pb) throw new Error(`unparseable version: ${!pa ? a : b}`);
  return pa[0] - pb[0] || pa[1] - pb[1] || pa[2] - pb[2] || pa[3] - pb[3];
}
