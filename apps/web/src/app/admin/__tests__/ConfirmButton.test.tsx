import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';

/**
 * ConfirmButton guards irreversible admin actions (re-extract wipes
 * staged cards; confirm-community changes what allergy users see).
 * The contract: a single click must NEVER fire the action — only the
 * explicit armed confirm does — and Cancel disarms.
 */
import { ConfirmButton } from '../_ConfirmButton';

describe('ConfirmButton', () => {
  it('requires the second, armed click before firing', () => {
    const onConfirm = vi.fn();
    render(<ConfirmButton label="Re-extract" onConfirm={onConfirm} testId="btn" />);

    fireEvent.click(screen.getByTestId('btn'));
    expect(onConfirm).not.toHaveBeenCalled();

    fireEvent.click(screen.getByTestId('btn-confirm'));
    expect(onConfirm).toHaveBeenCalledTimes(1);
  });

  it('cancel disarms without firing', () => {
    const onConfirm = vi.fn();
    render(<ConfirmButton label="Re-extract" onConfirm={onConfirm} testId="btn" />);

    fireEvent.click(screen.getByTestId('btn'));
    fireEvent.click(screen.getByTestId('btn-cancel'));

    expect(onConfirm).not.toHaveBeenCalled();
    expect(screen.getByTestId('btn')).toBeInTheDocument();
  });

  it('shows a disabled busy state while the action runs', () => {
    render(<ConfirmButton label="Re-extract" busy onConfirm={vi.fn()} testId="btn" />);
    expect(screen.getByTestId('btn')).toBeDisabled();
  });
});
