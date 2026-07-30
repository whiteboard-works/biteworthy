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
  onConfirm,
  testId,
}: {
  label: string;
  /** Copy on the armed button; defaults to "Confirm — <label>". */
  confirmLabel?: string;
  busyLabel?: string;
  busy?: boolean;
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

  const arm = () => {
    setArmed(true);
    disarmTimer.current = setTimeout(() => setArmed(false), ARM_TIMEOUT_MS);
  };

  const confirm = () => {
    if (disarmTimer.current) clearTimeout(disarmTimer.current);
    setArmed(false);
    onConfirm();
  };

  if (busy) {
    return (
      <button
        type="button"
        disabled
        data-testid={testId}
        className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1 text-bw-sm font-semibold text-zinc-500 opacity-60"
      >
        {busyLabel ?? `${label}…`}
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
        onClick={() => setArmed(false)}
        data-testid={`${testId}-cancel`}
        className="text-bw-sm font-semibold text-zinc-500 hover:text-zinc-800"
      >
        Cancel
      </button>
    </span>
  );
}
