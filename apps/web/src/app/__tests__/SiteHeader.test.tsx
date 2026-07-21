import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';

/**
 * The site-wide nav that gives a signed-in user any indication they're
 * logged in (and everyone a way to reach /login and /signup). Signed-in
 * state comes from GET /api/auth/session (fast, local); onboarding status
 * from GET /api/auth/onboarded (separate, so a slow API only delays the
 * nudge). A signed-in user who hasn't finished onboarding gets a
 * Food-profile link plus a dismissible banner; the dismissal is cleared
 * on logout so it never leaks to the next account on a shared browser.
 */

const mockReplace = vi.fn();
const mockRefresh = vi.fn();
vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: mockReplace, refresh: mockRefresh }),
  usePathname: () => '/',
}));

const mockLogout = vi.fn();
vi.mock('../../lib/auth', () => ({
  logout: () => mockLogout(),
}));

import { SiteHeader } from '../_SiteHeader';

const DISMISSED_KEY = 'bw_profile_nudge_dismissed';

function stubAuth({ signedIn, onboarded = true }: { signedIn: boolean; onboarded?: boolean }) {
  vi.stubGlobal(
    'fetch',
    vi.fn((url: string) =>
      Promise.resolve({
        ok: true,
        json: async () =>
          String(url).includes('/api/auth/onboarded') ? { onboarded } : { signedIn },
      }),
    ),
  );
}

beforeEach(() => {
  mockReplace.mockReset();
  mockRefresh.mockReset();
  mockLogout.mockReset().mockResolvedValue(undefined);
  localStorage.clear();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('SiteHeader', () => {
  it('shows Sign in + Sign up when signed out and never the account/scan controls', async () => {
    stubAuth({ signedIn: false });
    render(<SiteHeader />);
    expect(await screen.findByTestId('nav-signin')).toBeInTheDocument();
    expect(screen.getByTestId('nav-signup')).toBeInTheDocument();
    expect(screen.queryByTestId('nav-account')).not.toBeInTheDocument();
    expect(screen.queryByTestId('nav-logout')).not.toBeInTheDocument();
    expect(screen.queryByTestId('nav-scan')).not.toBeInTheDocument();
  });

  it('shows Scan + Account + Log out when signed in, and logging out returns home', async () => {
    stubAuth({ signedIn: true });
    render(<SiteHeader />);
    expect(await screen.findByTestId('nav-account')).toBeInTheDocument();
    // Signed-in users always get a path to the scanner (regardless of onboarding).
    expect(screen.getByTestId('nav-scan')).toHaveAttribute('href', '/ingest');
    expect(screen.queryByTestId('nav-signin')).not.toBeInTheDocument();

    await act(async () => {
      fireEvent.click(screen.getByTestId('nav-logout'));
    });

    await waitFor(() => expect(mockLogout).toHaveBeenCalledTimes(1));
    expect(mockReplace).toHaveBeenCalledWith('/');
  });

  it('does not nudge a signed-in user who has already onboarded', async () => {
    stubAuth({ signedIn: true, onboarded: true });
    render(<SiteHeader />);
    expect(await screen.findByTestId('nav-account')).toBeInTheDocument();
    expect(screen.queryByTestId('profile-nudge')).not.toBeInTheDocument();
    expect(screen.queryByTestId('nav-food-profile')).not.toBeInTheDocument();
  });

  it('nudges a signed-in user who has not onboarded, and Dismiss sticks', async () => {
    stubAuth({ signedIn: true, onboarded: false });
    render(<SiteHeader />);

    expect(await screen.findByTestId('profile-nudge')).toBeInTheDocument();
    expect(screen.getByTestId('nav-food-profile')).toBeInTheDocument();

    fireEvent.click(screen.getByTestId('profile-nudge-dismiss'));

    expect(screen.queryByTestId('profile-nudge')).not.toBeInTheDocument();
    expect(localStorage.getItem(DISMISSED_KEY)).toBe('1');
    // The quiet nav link stays even after the banner is dismissed.
    expect(screen.getByTestId('nav-food-profile')).toBeInTheDocument();
  });

  it('clears the dismissed flag on logout so the next account is nudged fresh', async () => {
    // A prior account already dismissed the banner on this browser.
    localStorage.setItem(DISMISSED_KEY, '1');
    stubAuth({ signedIn: true, onboarded: false });
    render(<SiteHeader />);

    // Not-onboarded but the stale dismissal suppresses the banner.
    expect(await screen.findByTestId('nav-food-profile')).toBeInTheDocument();
    expect(screen.queryByTestId('profile-nudge')).not.toBeInTheDocument();

    await act(async () => {
      fireEvent.click(screen.getByTestId('nav-logout'));
    });

    await waitFor(() => expect(mockLogout).toHaveBeenCalledTimes(1));
    expect(localStorage.getItem(DISMISSED_KEY)).toBeNull();
  });
});
