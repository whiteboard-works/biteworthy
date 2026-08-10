'use client';

import { useState } from 'react';
import { deleteErrorCopy } from '../../lib/admin/shared';
import { useIsSuperAdmin } from './_AdminTier';
import { ConfirmButton } from './_ConfirmButton';

/**
 * The permanent-delete control for the rows that have no archive of
 * their own — a review, a suggestion, a dish. Each already has a soft
 * path (hide with a reason, reject, `status: "removed"`), so the only
 * thing missing was destroying the row, and the control is the same
 * three lines every time.
 *
 * **Renders nothing for a plain admin.** Rails answers `?hard=true`
 * with a 404 for anyone below the super tier, so the button would exist
 * only to fail — the rule the promote/demote toggle set. This is UI
 * gating, not the gate: the server refuses regardless.
 *
 * The two-step `ConfirmButton` is the friction here. The heavier
 * type-the-name confirm is reserved for the two deletes that take other
 * records with them (a restaurant, a user account).
 */
export function HardDeleteButton({
  label = 'Delete',
  confirmLabel,
  onDelete,
  onDeleted,
  disabled = false,
  testId,
}: {
  label?: string;
  confirmLabel?: string;
  onDelete: () => Promise<unknown>;
  /** Called after the server confirms — the caller drops the row. */
  onDeleted: () => void;
  disabled?: boolean;
  testId: string;
}) {
  const isSuperAdmin = useIsSuperAdmin();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!isSuperAdmin) return null;

  const run = async () => {
    setBusy(true);
    setError(null);
    try {
      await onDelete();
      onDeleted();
    } catch (e) {
      setError(deleteErrorCopy(e, { hard: true }));
      // Only on failure: on success the row unmounts, and setting state
      // on an unmounted component is the classic warning here.
      setBusy(false);
    }
  };

  return (
    <span className="inline-flex flex-wrap items-center gap-bw-2">
      <ConfirmButton
        label={label}
        confirmLabel={confirmLabel ?? 'Confirm — delete forever'}
        busy={busy}
        disabled={disabled}
        onConfirm={() => void run()}
        testId={testId}
      />
      {error && (
        <span role="alert" data-testid={`${testId}-error`} className="text-bw-xs text-danger">
          {error}
        </span>
      )}
    </span>
  );
}
