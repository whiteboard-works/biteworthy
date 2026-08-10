'use client';

import type { ChangeEvent, ReactElement } from 'react';
import type { ChatMode } from '../../lib/chat';

/**
 * How much the user has agreed to in advance.
 *
 * Ordered loosest-to-strictest reading downward is the wrong instinct —
 * these run strictest first, so the list reads as a ladder of how much
 * the assistant may do without asking, which is the question someone is
 * actually answering when they open it.
 *
 * The descriptions are the contract, not decoration. Someone picking
 * `auto` is switching off the only place a destructive call stops for a
 * human, and the option has to say that before they pick it rather than
 * afterwards.
 */
const MODES: { value: ChatMode; label: string; hint: string }[] = [
  { value: 'planning', label: 'Planning', hint: 'Reads only. Proposes changes, never makes them.' },
  { value: 'manual', label: 'Manual', hint: 'Asks before anything destructive.' },
  {
    value: 'accept_edits',
    // Says what it waives, not just what it keeps. "Still asks before a
    // delete" was true and read as a much narrower promise than it is —
    // changes to your own avoid list go through silently under this mode,
    // and that is the one direction that can hurt somebody.
    label: 'Accept edits',
    hint: 'Menu and profile changes go through without asking — including removing something from your avoid list. Still asks before a delete.',
  },
  { value: 'auto', label: 'Auto', hint: 'Never asks.' },
];

export function ModePicker({
  mode,
  onChange,
}: {
  mode: ChatMode;
  onChange: (mode: ChatMode) => void;
}): ReactElement {
  const current = MODES.find((m) => m.value === mode);

  // A native select rather than a custom listbox: four short options with
  // a description each is exactly what one is for, and it comes with
  // keyboard and screen-reader behaviour that a div would have to
  // re-implement to be no better.
  return (
    <label className="flex items-center gap-bw-2">
      <span className="sr-only">Assistant mode</span>
      <select
        value={mode}
        data-testid="mode-picker"
        title={current?.hint}
        onChange={(event: ChangeEvent<HTMLSelectElement>) => onChange(event.target.value as ChatMode)}
        className="rounded-bw-md border border-zinc-300 bg-white px-bw-2 py-bw-1 text-bw-sm text-zinc-700 focus:border-bite focus:outline-none"
      >
        {MODES.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </label>
  );
}

/**
 * The line under the header, so the mode is legible without opening the
 * picker. Silent in manual — that is the default and the behaviour every
 * other part of the UI already describes.
 */
export function ModeNotice({ mode }: { mode: ChatMode }): ReactElement | null {
  if (mode === 'manual') return null;

  const option = MODES.find((m) => m.value === mode);
  if (!option) return null;

  return (
    <p
      data-testid="mode-notice"
      className={`border-b px-bw-4 py-bw-2 text-bw-sm ${
        mode === 'auto'
          ? 'border-danger/30 bg-danger/5 text-danger'
          : 'border-zinc-200 bg-zinc-50 text-zinc-600'
      }`}
    >
      <span className="font-medium">{option.label}:</span> {option.hint}
    </p>
  );
}
