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
  it('shows "Scan a menu" → /ingest when signed in', async () => {
    stubSession(true);
    render(<HeroCta />);

    const cta = await screen.findByTestId('cta-scan');
    expect(cta).toHaveAttribute('href', '/ingest');
    expect(screen.queryByTestId('cta-web')).not.toBeInTheDocument();
  });

  it('shows "Try the web app" → /onboarding when signed out', async () => {
    stubSession(false);
    render(<HeroCta />);

    expect(screen.getByTestId('cta-web')).toHaveAttribute('href', '/onboarding');
    await waitFor(() => expect(screen.queryByTestId('cta-scan')).not.toBeInTheDocument());
  });
});
