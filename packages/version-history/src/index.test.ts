import { describe, expect, it } from 'vitest';
import { compareVersions, parseVersion, VERSION_RE } from '../scripts/calver.mjs';
import { CURRENT_VERSION, VERSION_HISTORY } from './index';

/**
 * The calver contract, executable. Web and mobile render this data and
 * the footer version comes from it, so a malformed hand-edit must fail
 * CI, not ship. The format itself lives once in scripts/calver.mjs,
 * shared with the bump script — the writer can't drift from the
 * validator.
 */

describe('VERSION_HISTORY', () => {
  it('is non-empty and CURRENT_VERSION is the newest entry', () => {
    expect(VERSION_HISTORY.length).toBeGreaterThan(0);
    expect(CURRENT_VERSION).toBe(VERSION_HISTORY[0]!.version);
  });

  it('every version matches YYYY.M.D[.X] — non-padded, bump starting at 1', () => {
    for (const entry of VERSION_HISTORY) {
      // The shared regex rejects zero-padded months/days and a literal
      // `.0` bump (the first drop of a day is bare).
      expect(entry.version, entry.version).toMatch(VERSION_RE);
    }
  });

  it("every entry's ISO date is a real calendar date agreeing with its version", () => {
    for (const entry of VERSION_HISTORY) {
      const [y, mo, d] = parseVersion(entry.version)!;
      const iso = `${y}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
      expect(entry.date, entry.version).toBe(iso);
      // "2026.2.30" satisfies the shape but not the calendar — a Date
      // round-trip catches rollover and other impossible dates.
      expect(
        new Date(`${entry.date}T12:00:00Z`).toISOString().startsWith(entry.date),
        `${entry.version}: ${entry.date} is not a real calendar date`,
      ).toBe(true);
    }
  });

  it('entries are strictly descending — newest first, no duplicates', () => {
    for (let i = 1; i < VERSION_HISTORY.length; i++) {
      const newer = VERSION_HISTORY[i - 1]!.version;
      const older = VERSION_HISTORY[i]!.version;
      expect(compareVersions(newer, older), `${newer} must be newer than ${older}`).toBeGreaterThan(
        0,
      );
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
