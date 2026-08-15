import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';

const { track } = vi.hoisted(() => ({ track: vi.fn() }));

const mockReplace = vi.fn();
const mockGet = vi.fn();
vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: mockReplace }),
  useSearchParams: () => ({ get: mockGet }),
}));

const mockReset = vi.fn();
// Partial mock keeps the real AuthError so instanceof + status work.
vi.mock('../../../lib/auth', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../../lib/auth')>();
  return { ...actual, resetPassword: (...a: unknown[]) => mockReset(...a) };
});
vi.mock('../../_PostHogProvider', () => ({ useTracker: () => ({ track }) }));

import { AuthError } from '../../../lib/auth';
import ResetPasswordPage from '../page';

function submit() {
  const form = document.querySelector('form');
  if (!form) throw new Error('no form rendered');
  return act(async () => {
    fireEvent.submit(form);
  });
}

function fillPasswords(pw = 'newpass-123', confirm = pw) {
  fireEvent.change(screen.getByLabelText('new-password'), { target: { value: pw } });
  fireEvent.change(screen.getByLabelText('confirm-password'), { target: { value: confirm } });
}

beforeEach(() => {
  track.mockReset();
  mockReplace.mockReset();
  mockReset.mockReset();
  mockGet.mockReset().mockReturnValue('tok-123');
  window.history.replaceState(null, '', '/reset-password?reset_password_token=tok-123');
});

describe('ResetPasswordPage', () => {
  it('scrubs the token from the URL on mount — it must never reach analytics or history', async () => {
    render(<ResetPasswordPage />);
    await waitFor(() =>
      expect(window.location.search).not.toContain('reset_password_token'),
    );
  });

  it('consumes the captured token and lands on /login?reset=1', async () => {
    mockReset.mockResolvedValue(undefined);
    render(<ResetPasswordPage />);
    fillPasswords();
    await submit();

    await waitFor(() =>
      expect(mockReset).toHaveBeenCalledWith('tok-123', 'newpass-123', 'newpass-123'),
    );
    expect(track).toHaveBeenCalledWith('auth_completed', { method: 'password_reset' });
    expect(mockReplace).toHaveBeenCalledWith('/login?reset=1');
  });

  it('explains a rejected (expired/used) token and points at a fresh request', async () => {
    mockReset.mockRejectedValue(new AuthError(422, 'reset password token is invalid'));
    render(<ResetPasswordPage />);
    fillPasswords();
    await submit();

    await waitFor(() =>
      expect(screen.getByText(/request a new one below/i)).toBeInTheDocument(),
    );
    expect(track).toHaveBeenCalledWith('auth_failed', {
      method: 'password_reset',
      reason: 'token_rejected',
      status: 422,
    });
  });

  it('blocks mismatched passwords client-side', async () => {
    render(<ResetPasswordPage />);
    fillPasswords('newpass-123', 'different-99');
    await submit();

    expect(mockReset).not.toHaveBeenCalled();
    expect(screen.getByText(/do not match/i)).toBeInTheDocument();
  });

  it('renders the no-token explainer when opened without a link', () => {
    mockGet.mockReturnValue(null);
    window.history.replaceState(null, '', '/reset-password');
    render(<ResetPasswordPage />);
    expect(screen.getByTestId('reset-no-token')).toBeInTheDocument();
  });
});
