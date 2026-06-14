import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import ProfileSettingsPage from '../page';
import { OPT_OUT_KEY } from '../../../../lib/track';

/**
 * Legal remediation E7a — the analytics opt-out toggle the Privacy
 * Policy promises lives at /profile/settings. It must read + write the
 * same localStorage flag buildWebTracker honors.
 */
describe('ProfileSettingsPage — analytics toggle', () => {
  beforeEach(() => localStorage.clear());
  afterEach(() => localStorage.clear());

  it('defaults to analytics-on (no opt-out flag set)', async () => {
    render(<ProfileSettingsPage />);
    const toggle = (await screen.findByLabelText('analytics-opt-in')) as HTMLInputElement;
    expect(toggle.checked).toBe(true);
    expect(localStorage.getItem(OPT_OUT_KEY)).toBeNull();
  });

  it('writes the opt-out flag when toggled off, and clears it when toggled back on', async () => {
    render(<ProfileSettingsPage />);
    const toggle = (await screen.findByLabelText('analytics-opt-in')) as HTMLInputElement;

    fireEvent.click(toggle); // turn analytics OFF
    await waitFor(() => expect(localStorage.getItem(OPT_OUT_KEY)).toBe('1'));
    expect(screen.getByTestId('analytics-state')).toHaveTextContent(/opted out/i);

    fireEvent.click(screen.getByLabelText('analytics-opt-in')); // back ON
    await waitFor(() => expect(localStorage.getItem(OPT_OUT_KEY)).toBeNull());
  });

  it('reflects a pre-existing opt-out on load', async () => {
    localStorage.setItem(OPT_OUT_KEY, '1');
    render(<ProfileSettingsPage />);
    const toggle = (await screen.findByLabelText('analytics-opt-in')) as HTMLInputElement;
    expect(toggle.checked).toBe(false);
  });
});
