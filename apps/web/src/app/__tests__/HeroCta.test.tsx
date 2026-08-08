import { afterEach, describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { HeroCta } from '../_HeroCta';

function stubSession(signedIn: boolean) {
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({ ok: true, json: async () => ({ signedIn }) }),
  );
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('HeroCta', () => {
  // Scanning a menu is a conversation now, so the core action for a
  // signed-in user is the chat rather than an upload form.
  it('shows "Scan a menu" → /chat when signed in', async () => {
    stubSession(true);
    render(<HeroCta />);

    const cta = await screen.findByTestId('cta-scan');
    expect(cta).toHaveAttribute('href', '/chat');
    expect(screen.queryByTestId('cta-web')).not.toBeInTheDocument();
  });

  it('shows "Try the web app" → /onboarding when signed out', async () => {
    stubSession(false);
    render(<HeroCta />);

    expect(screen.getByTestId('cta-web')).toHaveAttribute('href', '/onboarding');
    await waitFor(() => expect(screen.queryByTestId('cta-scan')).not.toBeInTheDocument());
  });
});
