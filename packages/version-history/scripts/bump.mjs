#!/usr/bin/env node
/**
 * Prepend a new calver entry to src/history.json and print the version.
 *
 *   pnpm bump --note "Fixed X" --note "Added Y"
 *   pnpm bump --note="Fixed X"
 *
 * Scheme: YYYY.M.D (local date, non-padded). If the newest entry is
 * already today's, the new version appends/increments `.X` (first
 * same-day follow-up is `.1`). At least one --note is required — the
 * notes ship verbatim on the public /updates page, so there is no
 * placeholder path. Refuses to write anything that isn't strictly
 * newer than the current head. No git side effects — commit the result
 * in the version-bump PR.
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { compareVersions, parseVersion } from './calver.mjs';

const historyPath = join(dirname(fileURLToPath(import.meta.url)), '..', 'src', 'history.json');

const notes = [];
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  let value;
  if (args[i] === '--note') {
    value = args[i + 1];
    i++;
  } else if (args[i].startsWith('--note=')) {
    value = args[i].slice('--note='.length);
  } else {
    console.error(`unknown argument: ${args[i]} (use --note "…" or --note="…")`);
    process.exit(1);
  }
  if (!value || value.startsWith('--')) {
    console.error('--note requires a value (a flag or nothing followed it)');
    process.exit(1);
  }
  notes.push(value);
}
if (notes.length === 0) {
  console.error(
    'at least one --note "…" is required — the notes ship verbatim on the public /updates page',
  );
  process.exit(1);
}

const history = JSON.parse(readFileSync(historyPath, 'utf8'));

// Local date on purpose: versions are human-facing, and "today" means
// the releaser's today, not UTC's.
const now = new Date();
const today = `${now.getFullYear()}.${now.getMonth() + 1}.${now.getDate()}`;
const isoDate = [
  now.getFullYear(),
  String(now.getMonth() + 1).padStart(2, '0'),
  String(now.getDate()).padStart(2, '0'),
].join('-');

const newest = history[0]?.version ?? null;
if (newest !== null && parseVersion(newest) === null) {
  console.error(`newest entry "${newest}" doesn't parse as YYYY.M.D[.X] — fix history.json first`);
  process.exit(1);
}

let version = today;
if (newest !== null && compareVersions(newest, today) >= 0) {
  const head = parseVersion(newest);
  const day = parseVersion(today);
  if (head[0] !== day[0] || head[1] !== day[1] || head[2] !== day[2]) {
    // A head from the future means a clock problem or a bad hand-edit;
    // writing behind it would regress CURRENT_VERSION everywhere.
    console.error(
      `newest entry ${newest} is ahead of today (${today}) — check the clock or history.json`,
    );
    process.exit(1);
  }
  version = `${today}.${head[3] + 1}`;
}

history.unshift({ version, date: isoDate, notes });
writeFileSync(historyPath, `${JSON.stringify(history, null, 2)}\n`);
console.log(version);
