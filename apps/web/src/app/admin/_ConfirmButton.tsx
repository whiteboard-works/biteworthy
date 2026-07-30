'use client';

import { useEffect, useRef, useState } from 'react';

/**
 * Two-step inline confirm for irreversible admin actions — replaces
 * the window.alert() precedent without modal machinery. First click
 * arms the button ("Confirm — …? / Cancel"); it disarms itself after
 * 5s so a stray click can't linger as a landmine.
 */
const ARM_TIMEOUT_MS = 5_000;

export function ConfirmButton({
  label,
  confirmLabel,
  busyLabel,
  busy = false,
  disabled = false,
  onConfirm,
  testId,
}: {
  label: string;
  /** Copy on the armed button; defaults to "Confirm — <label>". */
  confirmLabel?: string;
  busyLabel?: string;
  busy?: boolean;
  /** e.g. a sibling action is mid-flight — render inert without the busy copy. */
  disabled?: boolean;
  onConfirm: () => void;
  testId: string;
}) {
  const [armed, setArmed] = useState(false);
  const disarmTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (disarmTimer.current) clearTimeout(disarmTimer.current);
    };
  }, []);

  // Every path that leaves the armed state must clear the timer, or a
  // cancel + quick re-arm inherits the OLD timeout and disarms early.
  const disarm = () => {
    if (disarmTimer.current) clearTimeout(disarmTimer.current);
    disarmTimer.current = null;
    setArmed(false);
  };

  const arm = () => {
    if (disarmTimer.current) clearTimeout(disarmTimer.current);
    setArmed(true);
    disarmTimer.current = setTimeout(disarm, ARM_TIMEOUT_MS);
  };

  const confirm = () => {
    disarm();
    onConfirm();
  };

  if (busy || disabled) {
    return (
      <button
        type="button"
        disabled
        data-testid={testId}
        className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1 text-bw-sm font-semibold text-zinc-500 opacity-60"
      >
        {busy ? (busyLabel ?? `${label}…`) : label}
      </button>
    );
  }

  if (!armed) {
    return (
      <button
        type="button"
        onClick={arm}
        data-testid={testId}
        className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1 text-bw-sm font-semibold text-zinc-700 hover:border-bite hover:text-bite"
      >
        {label}
      </button>
    );
  }

  return (
    <span className="inline-flex items-center gap-bw-2">
      <button
        type="button"
        onClick={confirm}
        data-testid={`${testId}-confirm`}
        className="rounded-bw-md bg-danger px-bw-3 py-bw-1 text-bw-sm font-bold text-white hover:opacity-90"
      >
        {confirmLabel ?? `Confirm — ${label}`}
      </button>
      <button
        type="button"
        onClick={disarm}
        data-testid={`${testId}-cancel`}
        className="text-bw-sm font-semibold text-zinc-500 hover:text-zinc-800"
      >
        Cancel
      </button>
    </span>
  );
}
