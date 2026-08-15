import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';

const { track } = vi.hoisted(() => ({ track: vi.fn() }));

const mockRequest = vi.fn();
vi.mock('../../../lib/auth', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../../lib/auth')>();
  return { ...actual, requestPasswordReset: (...a: unknown[]) => mockRequest(...a) };
});
vi.mock('../../_PostHogProvider', () => ({ useTracker: () => ({ track }) }));

import ForgotPasswordPage from '../page';

function submit() {
  const form = document.querySelector('form');
  if (!form) throw new Error('no form rendered');
  return act(async () => {
    fireEvent.submit(form);
  });
}

beforeEach(() => {
  track.mockReset();
  mockRequest.mockReset();
});

describe('ForgotPasswordPage', () => {
  it('shows the same non-committal confirmation whether or not the email exists', async () => {
    // The API answers 202 either way; this page must not narrow that.
    mockRequest.mockResolvedValue(undefined);
    render(<ForgotPasswordPage />);
    fireEvent.change(screen.getByLabelText('email'), { target: { value: 'x@y.com' } });
    await submit();

    await waitFor(() =>
      expect(screen.getByTestId('forgot-sent')).toHaveTextContent(
        /If .* has a BiteWorthy account/,
      ),
    );
    expect(track).toHaveBeenCalledWith('auth_started', { method: 'password_forgot' });
    expect(track).toHaveBeenCalledWith('auth_completed', { method: 'password_forgot' });
  });

  it('does not call the API on an empty submit', async () => {
    render(<ForgotPasswordPage />);
    await submit();
    expect(mockRequest).not.toHaveBeenCalled();
    expect(track).toHaveBeenCalledWith('auth_failed', {
      method: 'password_forgot',
      reason: 'missing_fields',
    });
  });
});
