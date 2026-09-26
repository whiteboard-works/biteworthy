import { afterEach, describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { HeroCta, TryADiet } from '../_HeroCta';
import { DURANGO_DIET_SLUGS } from '../../lib/durango';

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

/**
 * "Value before signup" — the zero-commitment path for a signed-out
 * visitor: a diet chip links straight to the already-filtered
 * `/durango/<diet>` page, no account required. Hidden once a
 * signed-in user (who already has a real profile) is confirmed.
 */
describe('TryADiet', () => {
  it('links every curated diet slug to its /durango/<diet> page when signed out', async () => {
    stubSession(false);
    render(<TryADiet />);

    const row = await screen.findByTestId('try-a-diet');
    expect(row).toBeInTheDocument();
    for (const slug of DURANGO_DIET_SLUGS) {
      expect(screen.getByTestId(`try-diet-${slug}`)).toHaveAttribute('href', `/durango/${slug}`);
    }
  });

  // A diet link's preset outranks a saved profile, so showing it to a
  // signed-in user with allergies could hand them a menu that ignores them.
  it('stays hidden until the session check confirms a signed-out visitor', () => {
    stubSession(false);
    render(<TryADiet />);
    expect(screen.queryByTestId('try-a-diet')).not.toBeInTheDocument();
  });

  it('stays hidden when the session check fails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, json: async () => ({}) }));
    render(<TryADiet />);
    await new Promise((r) => setTimeout(r, 0));
    expect(screen.queryByTestId('try-a-diet')).not.toBeInTheDocument();
  });

  it('stays hidden when the session check errors', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('offline')));
    render(<TryADiet />);
    await new Promise((r) => setTimeout(r, 0));
    expect(screen.queryByTestId('try-a-diet')).not.toBeInTheDocument();
  });

  it('hides once a signed-in user is confirmed', async () => {
    stubSession(true);
    render(<TryADiet />);
    await waitFor(() => expect(screen.queryByTestId('try-a-diet')).not.toBeInTheDocument());
  });
});
