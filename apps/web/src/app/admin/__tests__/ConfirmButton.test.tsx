import { afterEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen } from '@testing-library/react';

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

  it('renders inert (without busy copy) when a sibling action is mid-flight', () => {
    render(<ConfirmButton label="Re-extract" disabled onConfirm={vi.fn()} testId="btn" />);
    const btn = screen.getByTestId('btn');
    expect(btn).toBeDisabled();
    expect(btn).toHaveTextContent('Re-extract');
  });

  describe('with fake timers', () => {
    afterEach(() => {
      vi.useRealTimers();
    });

    it('auto-disarms after 5s, and a cancel does not cut a later re-arm short', () => {
      vi.useFakeTimers();
      render(<ConfirmButton label="Re-extract" onConfirm={vi.fn()} testId="btn" />);

      fireEvent.click(screen.getByTestId('btn'));
      act(() => void vi.advanceTimersByTime(5_001));
      expect(screen.queryByTestId('btn-confirm')).not.toBeInTheDocument();

      // Arm, cancel late in the window, immediately re-arm: the stale
      // timer must not disarm the fresh window early.
      fireEvent.click(screen.getByTestId('btn'));
      act(() => void vi.advanceTimersByTime(4_000));
      fireEvent.click(screen.getByTestId('btn-cancel'));
      fireEvent.click(screen.getByTestId('btn'));
      act(() => void vi.advanceTimersByTime(4_000));
      expect(screen.getByTestId('btn-confirm')).toBeInTheDocument();
    });
  });
});
