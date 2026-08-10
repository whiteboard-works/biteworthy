'use client';

import { useId, useState } from 'react';

/**
 * Confirm by typing the thing's name. Reserved for the two deletes that
 * take other records with them — a restaurant (its menus, items,
 * reviews, and everyone's saved rows) and a user account — where
 * `_ConfirmButton`'s two-step is not enough friction: both are one
 * mis-click away in a list of near-identical rows, and neither has an
 * undo.
 *
 * Comparison is trimmed and case-insensitive. The goal is to make the
 * operator read which row they are on, not to test their typing.
 */
export function TypeToConfirm({
  expected,
  label,
  busy = false,
  onConfirm,
  onCancel,
  testId,
}: {
  /** The name the operator must retype — usually the row's own name. */
  expected: string;
  label: string;
  busy?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
  testId: string;
}) {
  const [typed, setTyped] = useState('');
  const inputId = useId();
  const matches = typed.trim().toLowerCase() === expected.trim().toLowerCase();

  return (
    <div
      data-testid={testId}
      className="mt-bw-2 rounded-bw-md border border-danger bg-red-50 p-bw-3 text-bw-sm"
    >
      <label htmlFor={inputId} className="block text-red-900">
        This cannot be undone. Type <strong>{expected}</strong> to confirm.
      </label>
      <div className="mt-bw-2 flex flex-wrap items-center gap-bw-2">
        <input
          id={inputId}
          value={typed}
          onChange={(e) => setTyped(e.target.value)}
          autoComplete="off"
          data-testid={`${testId}-input`}
          className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1"
        />
        <button
          type="button"
          // Disabled rather than hidden: the operator can see the
          // button they are working toward, and a screen reader
          // announces why it is not yet available.
          disabled={!matches || busy}
          onClick={onConfirm}
          data-testid={`${testId}-confirm`}
          className="rounded-bw-md bg-danger px-bw-3 py-bw-1 font-bold text-white hover:opacity-90 disabled:opacity-50"
        >
          {busy ? `${label}…` : label}
        </button>
        <button
          type="button"
          onClick={onCancel}
          data-testid={`${testId}-cancel`}
          className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1 text-zinc-700"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}
