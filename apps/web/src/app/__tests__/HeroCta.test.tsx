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
  // Scanning moved to the tool layer and returns as a chat entry point;
  // until then a signed-in user is sent to browse, never to a dead /ingest.
  it('shows "Browse menus" → /restaurants when signed in', async () => {
    stubSession(true);
    render(<HeroCta />);

    const cta = await screen.findByTestId('cta-browse');
    expect(cta).toHaveAttribute('href', '/restaurants');
    expect(screen.queryByTestId('cta-web')).not.toBeInTheDocument();
    expect(screen.queryByTestId('cta-scan')).not.toBeInTheDocument();
  });

  it('shows "Try the web app" → /onboarding when signed out', async () => {
    stubSession(false);
    render(<HeroCta />);

    expect(screen.getByTestId('cta-web')).toHaveAttribute('href', '/onboarding');
    await waitFor(() => expect(screen.queryByTestId('cta-browse')).not.toBeInTheDocument());
  });
});
