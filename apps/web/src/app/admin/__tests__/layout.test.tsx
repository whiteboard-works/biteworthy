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

const mockJwtIsAdmin = vi.fn();
vi.mock('../../../lib/admin-auth', () => ({
  jwtIsAdmin: (jwt: string | null) => mockJwtIsAdmin(jwt),
}));

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

import AdminLayout from '../layout';

beforeEach(() => {
  mockGetServerJwt.mockReset();
  mockJwtIsAdmin.mockReset();
  mockRedirect.mockClear();
  mockNotFound.mockClear();
});

describe('AdminLayout', () => {
  it('redirects signed-out visitors to login with a return path, without an admin lookup', async () => {
    mockGetServerJwt.mockResolvedValue(null);
    await expect(AdminLayout({ children: <p /> })).rejects.toThrow('NEXT_REDIRECT');
    expect(mockRedirect).toHaveBeenCalledWith('/login?next=/admin');
    expect(mockJwtIsAdmin).not.toHaveBeenCalled();
  });

  it('404s anyone not confirmed as admin', async () => {
    mockGetServerJwt.mockResolvedValue('jwt-1');
    mockJwtIsAdmin.mockResolvedValue(false);
    await expect(AdminLayout({ children: <p /> })).rejects.toThrow('NEXT_NOT_FOUND');
    expect(mockJwtIsAdmin).toHaveBeenCalledWith('jwt-1');
  });

  it('renders the shell + nav + children for a confirmed admin', async () => {
    mockGetServerJwt.mockResolvedValue('jwt-1');
    mockJwtIsAdmin.mockResolvedValue(true);
    render(await AdminLayout({ children: <p data-testid="child">hi</p> }));
    expect(screen.getByTestId('admin-shell')).toBeInTheDocument();
    expect(screen.getByTestId('admin-nav')).toBeInTheDocument();
    expect(screen.getByTestId('child')).toBeInTheDocument();
  });
});
