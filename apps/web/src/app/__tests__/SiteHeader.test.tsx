import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';

/**
 * The site-wide nav that gives a signed-in user any indication they're
 * logged in (and everyone a way to reach /login). Auth state comes from
 * GET /api/auth/session; logout goes through lib/auth.
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

function stubSession(signedIn: boolean) {
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({ ok: true, json: async () => ({ signedIn }) }),
  );
}

beforeEach(() => {
  mockReplace.mockReset();
  mockRefresh.mockReset();
  mockLogout.mockReset().mockResolvedValue(undefined);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('SiteHeader', () => {
  it('shows Sign in when signed out and never the account controls', async () => {
    stubSession(false);
    render(<SiteHeader />);
    expect(await screen.findByTestId('nav-signin')).toBeInTheDocument();
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
});
