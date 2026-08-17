import { describe, expect, it } from 'vitest';
import { CURRENT_VERSION, VERSION_HISTORY } from './index';

/**
 * The calver contract, executable. Web and mobile render this data and
 * the footer version comes from it, so a malformed hand-edit must fail
 * CI, not ship.
 */

const VERSION_RE = /^(\d{4})\.(\d{1,2})\.(\d{1,2})(?:\.(\d+))?$/;

/** [year, month, day, bump] — bare versions are bump 0. */
function parts(version: string): [number, number, number, number] {
  const m = VERSION_RE.exec(version);
  if (!m) throw new Error(`unparseable version: ${version}`);
  return [Number(m[1]), Number(m[2]), Number(m[3]), m[4] ? Number(m[4]) : 0];
}

describe('VERSION_HISTORY', () => {
  it('is non-empty and CURRENT_VERSION is the newest entry', () => {
    expect(VERSION_HISTORY.length).toBeGreaterThan(0);
    expect(CURRENT_VERSION).toBe(VERSION_HISTORY[0]!.version);
  });

  it('every version matches YYYY.M.D[.X] with no zero-padding', () => {
    for (const entry of VERSION_HISTORY) {
      expect(entry.version, entry.version).toMatch(VERSION_RE);
      const m = VERSION_RE.exec(entry.version)!;
      // "2026.08.16" would sort and read wrong — month/day are bare numbers.
      expect(m[2], `${entry.version}: zero-padded month`).not.toMatch(/^0\d/);
      expect(m[3], `${entry.version}: zero-padded day`).not.toMatch(/^0\d/);
      if (m[4]) {
        // The first drop of a day is bare, so an explicit bump starts at 1.
        expect(Number(m[4]), `${entry.version}: bump must be >= 1`).toBeGreaterThanOrEqual(1);
      }
    }
  });

  it("every entry's ISO date agrees with its version's year/month/day", () => {
    for (const entry of VERSION_HISTORY) {
      const [y, mo, d] = parts(entry.version);
      const iso = `${y}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
      expect(entry.date, entry.version).toBe(iso);
    }
  });

  it('entries are strictly descending — newest first, no duplicates', () => {
    for (let i = 1; i < VERSION_HISTORY.length; i++) {
      const newer = parts(VERSION_HISTORY[i - 1]!.version);
      const older = parts(VERSION_HISTORY[i]!.version);
      const cmp =
        newer[0] - older[0] || newer[1] - older[1] || newer[2] - older[2] || newer[3] - older[3];
      expect(
        cmp,
        `${VERSION_HISTORY[i - 1]!.version} must be newer than ${VERSION_HISTORY[i]!.version}`,
      ).toBeGreaterThan(0);
    }
  });

  it('every entry has at least one non-empty note', () => {
    for (const entry of VERSION_HISTORY) {
      expect(entry.notes.length, entry.version).toBeGreaterThan(0);
      for (const note of entry.notes) {
        expect(note.trim().length, entry.version).toBeGreaterThan(0);
      }
    }
  });
});
