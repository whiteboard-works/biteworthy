import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';

/**
 * The site-wide nav that gives a signed-in user any indication they're
 * logged in (and everyone a way to reach /login and /signup). Auth state
 * comes from GET /api/auth/session; logout goes through lib/auth. A
 * signed-in user who hasn't finished onboarding gets a Food-profile link
 * plus a dismissible nudge.
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

function stubSession(signedIn: boolean, onboarded = true) {
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({ ok: true, json: async () => ({ signedIn, onboarded }) }),
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
  it('shows Sign in + Sign up when signed out and never the account controls', async () => {
    stubSession(false);
    render(<SiteHeader />);
    expect(await screen.findByTestId('nav-signin')).toBeInTheDocument();
    expect(screen.getByTestId('nav-signup')).toBeInTheDocument();
    expect(screen.queryByTestId('nav-account')).not.toBeInTheDocument();
    expect(screen.queryByTestId('nav-logout')).not.toBeInTheDocument();
  });

  it('shows Account + Log out when signed in, and logging out returns home', async () => {
    stubSession(true);
    render(<SiteHeader />);
    expect(await screen.findByTestId('nav-account')).toBeInTheDocument();
    expect(screen.queryByTestId('nav-signin')).not.toBeInTheDocument();

    await act(async () => {
      fireEvent.click(screen.getByTestId('nav-logout'));
    });

    await waitFor(() => expect(mockLogout).toHaveBeenCalledTimes(1));
    expect(mockReplace).toHaveBeenCalledWith('/');
  });

  it('does not nudge a signed-in user who has already onboarded', async () => {
    stubSession(true, true);
    render(<SiteHeader />);
    expect(await screen.findByTestId('nav-account')).toBeInTheDocument();
    expect(screen.queryByTestId('profile-nudge')).not.toBeInTheDocument();
    expect(screen.queryByTestId('nav-food-profile')).not.toBeInTheDocument();
  });

  it('nudges a signed-in user who has not onboarded, and Dismiss sticks', async () => {
    stubSession(true, false);
    render(<SiteHeader />);

    expect(await screen.findByTestId('profile-nudge')).toBeInTheDocument();
    expect(screen.getByTestId('nav-food-profile')).toBeInTheDocument();

    fireEvent.click(screen.getByTestId('profile-nudge-dismiss'));

    expect(screen.queryByTestId('profile-nudge')).not.toBeInTheDocument();
    expect(localStorage.getItem('bw_profile_nudge_dismissed')).toBe('1');
    // The quiet nav link stays even after the banner is dismissed.
    expect(screen.getByTestId('nav-food-profile')).toBeInTheDocument();
  });
});
