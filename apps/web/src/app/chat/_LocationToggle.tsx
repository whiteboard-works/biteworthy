'use client';

import type { ReactElement } from 'react';
import type { LocationStatus } from './_useDeviceLocation';

const NOTE: Partial<Record<LocationStatus, string>> = {
  locating: 'Finding your location…',
  denied: 'Location is blocked for this site. Allow it in your browser settings, or name a city.',
  unavailable: 'Could not get your location. Name a city instead.',
};

interface Props {
  status: LocationStatus;
  onToggle: () => void;
}

/** "Use my location", in the chat header so the composer row stays
 *  wide enough to type in on a phone. */
export function LocationToggle({ status, onToggle }: Props): ReactElement {
  const lit = status === 'on' || status === 'locating';
  return (
    <button
      type="button"
      onClick={onToggle}
      aria-pressed={lit}
      aria-label="Use my location"
      title={
        status === 'on'
          ? 'Sending your approximate location with each message. Tap to stop.'
          : 'Send your approximate location with each message, for “near me”.'
      }
      className={`rounded-bw-md border px-bw-2 py-bw-1 text-bw-sm ${
        status === 'on'
          ? 'border-bite bg-bite-light text-bite-dark'
          : 'border-zinc-300 text-zinc-700 hover:bg-zinc-50'
      }`}
    >
      <span aria-hidden="true">📍</span>
      <span className="ml-bw-1 hidden sm:inline">Near me</span>
    </button>
  );
}

export function LocationNote({ status }: { status: LocationStatus }): ReactElement | null {
  const note = NOTE[status];
  if (!note) return null;
  return (
    <p role="status" className="border-b border-zinc-200 px-bw-4 py-bw-1 text-bw-sm text-zinc-500">
      {note}
    </p>
  );
}
