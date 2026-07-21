import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';

/**
 * Auth funnel analytics on the signup form. Each client-side gate
 * (weak password, age, terms) reports its own coarse reason so we can
 * see which one blocks people; the API failure path reports email_taken
 * with the 422 status. No email or password is ever sent.
 */

const { track } = vi.hoisted(() => ({ track: vi.fn() }));

const mockReplace = vi.fn();
const mockGet = vi.fn();
vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: mockReplace }),
  useSearchParams: () => ({ get: mockGet }),
}));

const mockSignup = vi.fn();
vi.mock('../../../lib/auth', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../../lib/auth')>();
  return { ...actual, signup: (...a: unknown[]) => mockSignup(...a) };
});

vi.mock('../../_PostHogProvider', () => ({ useTracker: () => ({ track }) }));

import { AuthError } from '../../../lib/auth';
import SignupPage from '../page';

function submit() {
  const form = document.querySelector('form');
  if (!form) throw new Error('no form rendered');
  return act(async () => {
    fireEvent.submit(form);
  });
}

function fill({
  email = 'a@b.com',
  password = 'secret12',
  age = true,
  terms = true,
}: { email?: string; password?: string; age?: boolean; terms?: boolean } = {}) {
  fireEvent.change(screen.getByLabelText('email'), { target: { value: email } });
  fireEvent.change(screen.getByLabelText('password'), { target: { value: password } });
  if (age) fireEvent.click(screen.getByTestId('age-confirm'));
  if (terms) fireEvent.click(screen.getByTestId('terms-accept'));
}

beforeEach(() => {
  track.mockReset();
  mockReplace.mockReset();
  mockGet.mockReset().mockReturnValue(null);
  mockSignup.mockReset();
});

describe('SignupPage analytics', () => {
  it('tracks auth_started then auth_completed on a successful sign-up', async () => {
    mockSignup.mockResolvedValue({});
    render(<SignupPage />);
    fill();
    await submit();

    await waitFor(() => expect(mockSignup).toHaveBeenCalledTimes(1));
    expect(track).toHaveBeenCalledWith('auth_started', { method: 'signup' });
    expect(track).toHaveBeenCalledWith('auth_completed', { method: 'signup' });
    expect(mockReplace).toHaveBeenCalledWith('/onboarding');
  });

  it('tracks auth_failed:weak_password before hitting the API', async () => {
    render(<SignupPage />);
    fill({ password: 'short' });
    await submit();

    expect(track).toHaveBeenCalledWith('auth_failed', { method: 'signup', reason: 'weak_password' });
    expect(mockSignup).not.toHaveBeenCalled();
  });

  it('tracks auth_failed:terms_unaccepted — and the submit stays reachable so it fires', async () => {
    render(<SignupPage />);
    fill({ terms: false });
    // The gate must be REACHABLE — a disabled button would emit nothing.
    expect(screen.getByTestId('signup-submit')).not.toBeDisabled();
    await submit();

    expect(track).toHaveBeenCalledWith('auth_failed', {
      method: 'signup',
      reason: 'terms_unaccepted',
    });
    expect(mockSignup).not.toHaveBeenCalled();
  });

  it('tracks auth_failed:rejected with the 422 status (422 is any server validation failure)', async () => {
    mockSignup.mockRejectedValue(new AuthError(422, 'taken'));
    render(<SignupPage />);
    fill();
    await submit();

    await waitFor(() =>
      expect(track).toHaveBeenCalledWith('auth_failed', {
        method: 'signup',
        reason: 'rejected',
        status: 422,
      }),
    );
    expect(track).not.toHaveBeenCalledWith('auth_completed', { method: 'signup' });
  });
});
