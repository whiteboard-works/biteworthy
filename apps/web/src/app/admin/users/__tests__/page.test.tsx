import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, within } from '@testing-library/react';

/**
 * The users page is where admin power changes hands, so the pins are:
 * promote/demote fires only through the two-step confirm with the
 * server-returned row swap, and the server's self-demotion refusal
 * surfaces as instructions rather than a generic failure.
 */

const mockFetchUsers = vi.fn();
const mockSetAdmin = vi.fn();
const mockDestroyUser = vi.fn();
vi.mock('../../../../lib/admin/deletes', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../lib/admin/deletes')>()),
  destroyAdminUser: (id: string) => mockDestroyUser(id),
}));
vi.mock('../../../../lib/admin/management', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../../../lib/admin/management')>()),
  fetchAdminUsers: (q: unknown) => mockFetchUsers(q),
  setUserAdmin: (id: string, v: boolean) => mockSetAdmin(id, v),
}));

import AdminUsersPage from '../page';
import { AdminTierProvider } from '../../_AdminTier';
import { AdminError } from '../../../../lib/admin/shared';

/** The layout supplies the tier in production; the tests supply it here. */
function renderAsTier(isSuperAdmin: boolean) {
  return render(
    <AdminTierProvider isSuperAdmin={isSuperAdmin}>
      <AdminUsersPage />
    </AdminTierProvider>,
  );
}

function user(overrides: Record<string, unknown> = {}) {
  return {
    id: 'u1',
    email: 'diner@example.com',
    handle: 'diner_1',
    display_name: null,
    provider: null,
    is_admin: false,
    created_at: '2026-07-30T12:00:00Z',
    reviews_count: 2,
    ingestion_runs_count: 1,
    ...overrides,
  };
}

function payload(users: unknown[]) {
  return { users, pagination: { total: users.length, limit: 25, offset: 0 } };
}

beforeEach(() => {
  mockFetchUsers.mockReset();
  mockSetAdmin.mockReset();
  mockDestroyUser.mockReset();
});

describe('AdminUsersPage', () => {
  it('promotes through the two-step confirm and swaps to the server state', async () => {
    mockFetchUsers.mockResolvedValue(payload([user()]));
    // The PATCH response omits the contribution counts — the page's
    // merge must preserve them (a bare replace would zero the row).
    const { reviews_count: _r, ingestion_runs_count: _i, ...patched } = user({ is_admin: true });
    mockSetAdmin.mockResolvedValue(patched);
    render(<AdminUsersPage />);
    const row = await screen.findByTestId('user-row-diner_1');

    fireEvent.click(within(row).getByTestId('user-toggle-diner_1'));
    expect(mockSetAdmin).not.toHaveBeenCalled();

    fireEvent.click(within(row).getByTestId('user-toggle-diner_1-confirm'));

    // Wait for the settled (post-busy) state — the row now offers Demote
    // and wears the admin badge from the server-returned payload.
    await vi.waitFor(() =>
      expect(within(row).getByTestId('user-toggle-diner_1')).toHaveTextContent('Demote'),
    );
    expect(mockSetAdmin).toHaveBeenCalledWith('u1', true);
    expect(within(row).getByTestId('status-badge')).toHaveTextContent('admin');
    expect(row).toHaveTextContent('2 reviews');
  });

  it('maps the self-demotion refusal to instructions', async () => {
    mockFetchUsers.mockResolvedValue(payload([user({ is_admin: true, handle: 'me' })]));
    mockSetAdmin.mockRejectedValue(new AdminError('x', 422, 'cannot_demote_self'));
    render(<AdminUsersPage />);
    const row = await screen.findByTestId('user-row-me');

    fireEvent.click(within(row).getByTestId('user-toggle-me'));
    fireEvent.click(within(row).getByTestId('user-toggle-me-confirm'));

    expect(await screen.findByTestId('users-error')).toHaveTextContent(
      'You cannot demote yourself',
    );
    // Still an admin — nothing changed locally.
    expect(row).toHaveTextContent('admin');
  });

  // The super tier is granted and revoked from a shell, so the API
  // refuses the toggle. Rendering a control that always fails would be
  // worse than rendering none, and the refusal must not read as a
  // page-load failure — `friendlyAdminError` turns an unrecognised 422
  // into "Something went wrong loading admin data", which is a lie about
  // a deliberate rule.
  it('hides the toggle for a super admin and says where it is managed', async () => {
    mockFetchUsers.mockResolvedValue(
      payload([user({ is_admin: true, is_super_admin: true, handle: 'boss' })]),
    );
    render(<AdminUsersPage />);
    const row = await screen.findByTestId('user-row-boss');

    expect(within(row).queryByTestId('user-toggle-boss')).toBeNull();
    expect(within(row).getByTestId('status-badge')).toHaveTextContent('super admin');
    expect(row).toHaveTextContent('Managed on the server');
  });

  it('maps the super-admin refusal to instructions rather than a generic failure', async () => {
    mockFetchUsers.mockResolvedValue(payload([user({ is_admin: true, handle: 'boss' })]));
    mockSetAdmin.mockRejectedValue(new AdminError('x', 422, 'cannot_demote_super_admin'));
    render(<AdminUsersPage />);
    const row = await screen.findByTestId('user-row-boss');

    fireEvent.click(within(row).getByTestId('user-toggle-boss'));
    fireEvent.click(within(row).getByTestId('user-toggle-boss-confirm'));

    expect(await screen.findByTestId('users-error')).toHaveTextContent('admin:revoke_super');
  });

  it('search sends q and resets paging', async () => {
    mockFetchUsers.mockResolvedValue(payload([]));
    render(<AdminUsersPage />);
    await screen.findByTestId('users-search');

    fireEvent.change(screen.getByTestId('users-search'), { target: { value: 'skylar' } });

    await vi.waitFor(() =>
      expect(mockFetchUsers).toHaveBeenLastCalledWith(
        expect.objectContaining({ q: 'skylar', offset: 0 }),
      ),
    );
  });

  // Deleting an account destroys the profile, reviews, saved rows,
  // overrides, visits and conversations. There is no archive to fall
  // back to, so the friction is typing the handle — and the control is
  // not offered at all to an admin the server would refuse.
  describe('deleting an account', () => {
    it('is not offered to a plain admin', async () => {
      mockFetchUsers.mockResolvedValue(payload([user({ handle: 'diner_1' })]));
      renderAsTier(false);
      const row = await screen.findByTestId('user-row-diner_1');

      expect(within(row).queryByTestId('user-delete-diner_1')).toBeNull();
    });

    it('needs the handle typed, then refetches without the row', async () => {
      // Refetch, not a local filter: dropping the row client-side
      // leaves `offset` on the old window and skips whoever slid into
      // the deleted user's index.
      mockFetchUsers.mockResolvedValueOnce(payload([user({ handle: 'diner_1' })]));
      mockFetchUsers.mockResolvedValue(payload([]));
      mockDestroyUser.mockResolvedValue({ id: 'u1', deleted: true });
      renderAsTier(true);
      const row = await screen.findByTestId('user-row-diner_1');

      fireEvent.click(within(row).getByTestId('user-delete-diner_1'));
      const panel = await screen.findByTestId('user-delete-confirm-diner_1');
      expect(within(panel).getByTestId('user-delete-confirm-diner_1-confirm')).toBeDisabled();

      fireEvent.change(within(panel).getByTestId('user-delete-confirm-diner_1-input'), {
        target: { value: 'diner_1' },
      });
      fireEvent.click(within(panel).getByTestId('user-delete-confirm-diner_1-confirm'));

      await vi.waitFor(() => expect(mockDestroyUser).toHaveBeenCalledWith('u1'));
      await vi.waitFor(() => expect(screen.queryByTestId('user-row-diner_1')).toBeNull());
      // The row vanishing proves nothing on its own — a local filter
      // does that too, and leaves `offset` on the stale window. What
      // has to be true is that the list was re-read from the server.
      expect(mockFetchUsers).toHaveBeenCalledTimes(2);
    });

    // A 404 here means "not a super admin", not "your access is gone" —
    // the generic copy would send the operator to sign in again, which
    // fixes nothing.
    it('does not claim a 404 was a tier refusal', async () => {
      mockFetchUsers.mockResolvedValue(payload([user({ handle: 'diner_1' })]));
      mockDestroyUser.mockRejectedValue(new AdminError('x', 404));
      renderAsTier(true);
      const row = await screen.findByTestId('user-row-diner_1');

      fireEvent.click(within(row).getByTestId('user-delete-diner_1'));
      fireEvent.change(screen.getByTestId('user-delete-confirm-diner_1-input'), {
        target: { value: 'diner_1' },
      });
      fireEvent.click(screen.getByTestId('user-delete-confirm-diner_1-confirm'));

      expect(await screen.findByTestId('users-error')).toHaveTextContent(/already be gone/i);
      expect(screen.getByTestId('user-row-diner_1')).toBeInTheDocument();
    });
  });
});
