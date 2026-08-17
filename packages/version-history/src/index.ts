/**
 * The product's version history — calver `YYYY.M.D[.X]`, newest-first.
 *
 * `history.json` is the single source of truth: `pnpm bump` (or
 * `scripts/bump.mjs` directly) prepends an entry, humans edit the
 * notes, and web + mobile render from these exports. The scheme:
 * year.month.day, non-padded; the first drop of a day is bare and
 * same-day follow-ups append `.1`, `.2`, … — `src/index.test.ts`
 * enforces all of it, so a bad hand-edit fails CI instead of shipping.
 */

import history from './history.json';

export interface VersionEntry {
  /** `YYYY.M.D` or `YYYY.M.D.X`, non-padded (e.g. "2026.8.16.1"). */
  version: string;
  /** ISO date of the drop — always consistent with `version`'s Y/M/D. */
  date: string;
  /** User-facing notes: what changed, in plain language. */
  notes: string[];
}

// Explicitly `readonly VersionEntry[]` (not `satisfies`): the array is
// a process-wide singleton — a consumer calling .sort()/.reverse() must
// not compile, and a stray key in the JSON must not silently widen the
// type.
export const VERSION_HISTORY: readonly VersionEntry[] = history;

// The history is seeded non-empty and the contract test keeps it that
// way, so the newest entry always exists.
export const CURRENT_VERSION = VERSION_HISTORY[0]!.version;
