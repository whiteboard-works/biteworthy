import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';

/**
 * The /admin layout is the only thing standing between the admin shell
 * and every visitor: signed-out → login redirect with a return path,
 * anyone not CONFIRMED as admin → the site's standard 404 (never a
 * "forbidden" that advertises the surface exists). Rails still gates
 * every data call; this pins the UX contract.
 */

const mockGetServerJwt = vi.fn();
vi.mock('../../../lib/server-auth', () => ({
  getServerJwt: () => mockGetServerJwt(),
}));

const mockAdminIdentity = vi.fn();
vi.mock('../../../lib/admin-auth', () => ({
  adminIdentity: (jwt: string | null) => mockAdminIdentity(jwt),
}));

/** The layout reads status + tier from one call; most cases only care about status. */
const identity = (status: string, isSuperAdmin = false) => ({ status, isSuperAdmin });

const mockRedirect = vi.fn((_target: string): never => {
  throw new Error('NEXT_REDIRECT');
});
const mockNotFound = vi.fn((): never => {
  throw new Error('NEXT_NOT_FOUND');
});
vi.mock('next/navigation', () => ({
  redirect: (target: string) => mockRedirect(target),
  notFound: () => mockNotFound(),
  usePathname: () => '/admin',
}));

import AdminLayout, { dynamic, metadata } from '../layout';

beforeEach(() => {
  mockGetServerJwt.mockReset();
  mockAdminIdentity.mockReset();
  mockRedirect.mockClear();
  mockNotFound.mockClear();
});

describe('AdminLayout', () => {
  it('redirects visitors without a usable session to login with a return path', async () => {
    mockGetServerJwt.mockResolvedValue(null);
    mockAdminIdentity.mockResolvedValue(identity('unauthenticated'));
    await expect(AdminLayout({ children: <p /> })).rejects.toThrow('NEXT_REDIRECT');
    expect(mockRedirect).toHaveBeenCalledWith('/login?next=/admin');
  });

  it('redirects an expired/revoked session (upstream 401) to login, not a 404', async () => {
    mockGetServerJwt.mockResolvedValue('stale-jwt');
    mockAdminIdentity.mockResolvedValue(identity('unauthenticated'));
    await expect(AdminLayout({ children: <p /> })).rejects.toThrow('NEXT_REDIRECT');
    expect(mockNotFound).not.toHaveBeenCalled();
  });

  it('404s anyone not confirmed as admin', async () => {
    mockGetServerJwt.mockResolvedValue('jwt-1');
    mockAdminIdentity.mockResolvedValue(identity('denied'));
    await expect(AdminLayout({ children: <p /> })).rejects.toThrow('NEXT_NOT_FOUND');
    expect(mockAdminIdentity).toHaveBeenCalledWith('jwt-1');
  });

  it('renders the shell + nav + children for a confirmed admin', async () => {
    mockGetServerJwt.mockResolvedValue('jwt-1');
    mockAdminIdentity.mockResolvedValue(identity('admin'));
    render(await AdminLayout({ children: <p data-testid="child">hi</p> }));
    expect(screen.getByTestId('admin-shell')).toBeInTheDocument();
    expect(screen.getByTestId('admin-nav')).toBeInTheDocument();
    expect(screen.getByTestId('child')).toBeInTheDocument();
  });

  it('keeps the no-prerender + noindex exports the docstring calls load-bearing', () => {
    expect(dynamic).toBe('force-dynamic');
    expect(metadata.robots).toEqual({ index: false, follow: false });
  });
});
