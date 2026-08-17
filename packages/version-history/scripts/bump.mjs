#!/usr/bin/env node
/**
 * Prepend a new calver entry to src/history.json and print the version.
 *
 *   pnpm bump                          # from the repo root (alias)
 *   pnpm bump --note "Fixed X" --note "Added Y"
 *
 * Scheme: YYYY.M.D (local date, non-padded). If the newest entry is
 * already today's, the new version appends/increments `.X` (first
 * same-day follow-up is `.1`). No git side effects — commit the result
 * in the version-bump PR and replace the TODO note if none was given.
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const historyPath = join(dirname(fileURLToPath(import.meta.url)), '..', 'src', 'history.json');

const notes = [];
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--note') {
    const value = args[i + 1];
    if (!value) {
      console.error('--note requires a value');
      process.exit(1);
    }
    notes.push(value);
    i++;
  } else {
    console.error(`unknown argument: ${args[i]} (only --note "…" is supported)`);
    process.exit(1);
  }
}
if (notes.length === 0) notes.push('TODO: describe this drop');

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

const newest = history[0]?.version ?? '';
let version = today;
if (newest === today || newest.startsWith(`${today}.`)) {
  const bump = newest === today ? 0 : Number(newest.slice(today.length + 1));
  if (!Number.isInteger(bump)) {
    console.error(`cannot parse newest version "${newest}" as today's — fix history.json first`);
    process.exit(1);
  }
  version = `${today}.${bump + 1}`;
}

history.unshift({ version, date: isoDate, notes });
writeFileSync(historyPath, `${JSON.stringify(history, null, 2)}\n`);
console.log(version);
