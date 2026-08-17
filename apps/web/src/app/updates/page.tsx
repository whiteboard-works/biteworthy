import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { VERSION_HISTORY, type VersionEntry } from '@biteworthy/version-history';
import { buildLegalMetadata } from '../../lib/legal-meta';

/**
 * The public version history. Pure SSR over
 * `@biteworthy/version-history` — one block per drop, newest first.
 * Versions are calver (`YYYY.M.D[.X]`); the package's contract test
 * keeps the data well-formed, so this page just renders.
 */

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? 'https://bite-worthy.com';

export const metadata: Metadata = buildLegalMetadata({
  pageTitle: "What's new",
  description:
    "BiteWorthy's version history — every drop, dated year.month.day, with what changed in plain language.",
  path: '/updates',
  siteUrl: SITE_URL,
});

function humanDate(iso: string): string {
  // Noon UTC so the calendar date can't shift in any timezone.
  return new Date(`${iso}T12:00:00Z`).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    timeZone: 'UTC',
  });
}

export default function UpdatesPage(): ReactElement {
  return (
    <main className="mx-auto max-w-3xl px-bw-6 pt-bw-12 pb-bw-16">
      <p className="text-bite text-bw-sm font-bold uppercase tracking-[0.2em]">Version history</p>
      <h1 className="mt-bw-3 text-bw-3xl font-bold text-zinc-900 md:text-bw-4xl">
        What&rsquo;s new
      </h1>
      <p className="mt-bw-4 text-bw-base text-zinc-700">
        Every BiteWorthy drop, newest first. Versions are dates — year.month.day, with a final
        number when more than one drop lands in a day.
      </p>

      <ol className="mt-bw-8 flex flex-col gap-bw-8">
        {VERSION_HISTORY.map((entry: VersionEntry) => (
          <li key={entry.version} data-testid={`release-${entry.version}`}>
            <h2 className="text-bw-xl font-bold text-zinc-900">v{entry.version}</h2>
            <p className="mt-bw-1 text-bw-sm text-zinc-500">{humanDate(entry.date)}</p>
            <ul className="mt-bw-3 list-disc space-y-bw-2 pl-bw-5 text-bw-base text-zinc-700">
              {entry.notes.map((note) => (
                <li key={note}>{note}</li>
              ))}
            </ul>
          </li>
        ))}
      </ol>
    </main>
  );
}
