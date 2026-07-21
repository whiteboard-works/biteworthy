import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';

/**
 * Auth funnel analytics on the login form: every submit fires
 * auth_started, then exactly one of auth_completed / auth_failed with a
 * coarse, PII-free reason. Forms are submitted via fireEvent.submit so
 * the handler runs regardless of jsdom's required-field handling.
 */

const { track } = vi.hoisted(() => ({ track: vi.fn() }));

const mockReplace = vi.fn();
const mockGet = vi.fn();
vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: mockReplace }),
  useSearchParams: () => ({ get: mockGet }),
}));

const mockLogin = vi.fn();
// Partial mock: keep the real AuthError so `err instanceof AuthError`
// (and its status) works; override only the network call.
vi.mock('../../../lib/auth', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../../lib/auth')>();
  return { ...actual, login: (...a: unknown[]) => mockLogin(...a) };
});

vi.mock('../../_PostHogProvider', () => ({ useTracker: () => ({ track }) }));

import { AuthError } from '../../../lib/auth';
import LoginPage from '../page';

function submit() {
  const form = document.querySelector('form');
  if (!form) throw new Error('no form rendered');
  return act(async () => {
    fireEvent.submit(form);
  });
}

function fillCredentials(email = 'a@b.com', password = 'secret12') {
  fireEvent.change(screen.getByLabelText('email'), { target: { value: email } });
  fireEvent.change(screen.getByLabelText('password'), { target: { value: password } });
}

beforeEach(() => {
  track.mockReset();
  mockReplace.mockReset();
  mockGet.mockReset().mockReturnValue(null);
  mockLogin.mockReset();
});

describe('LoginPage analytics', () => {
  it('tracks auth_started then auth_completed on a successful sign-in', async () => {
    mockLogin.mockResolvedValue({});
    render(<LoginPage />);
    fillCredentials();
    await submit();

    await waitFor(() => expect(mockLogin).toHaveBeenCalledTimes(1));
    expect(track).toHaveBeenCalledWith('auth_started', { method: 'login' });
    expect(track).toHaveBeenCalledWith('auth_completed', { method: 'login' });
    expect(mockReplace).toHaveBeenCalledWith('/');
  });

  it('tracks auth_failed:missing_fields without calling the API when empty', async () => {
    render(<LoginPage />);
    await submit();

    expect(track).toHaveBeenCalledWith('auth_started', { method: 'login' });
    expect(track).toHaveBeenCalledWith('auth_failed', { method: 'login', reason: 'missing_fields' });
    expect(mockLogin).not.toHaveBeenCalled();
  });

  it('tracks auth_failed:wrong_credentials with the 401 status', async () => {
    mockLogin.mockRejectedValue(new AuthError(401, 'nope'));
    render(<LoginPage />);
    fillCredentials();
    await submit();

    await waitFor(() =>
      expect(track).toHaveBeenCalledWith('auth_failed', {
        method: 'login',
        reason: 'wrong_credentials',
        status: 401,
      }),
    );
    expect(track).not.toHaveBeenCalledWith('auth_completed', { method: 'login' });
  });

  it('tracks auth_failed:network (no status) when the request never reaches the API', async () => {
    mockLogin.mockRejectedValue(new Error('fetch failed'));
    render(<LoginPage />);
    fillCredentials();
    await submit();

    await waitFor(() =>
      expect(track).toHaveBeenCalledWith('auth_failed', { method: 'login', reason: 'network' }),
    );
  });
});
