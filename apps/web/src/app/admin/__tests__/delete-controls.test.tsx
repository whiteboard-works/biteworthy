import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';

/**
 * The two controls the delete surface is built from, plus the error
 * copy that decides what a 404 means.
 *
 * The tier gate is the load-bearing one. Rails answers `?hard=true`
 * from a plain admin with a 404 — the same 404 it gives a non-admin —
 * so a button that renders for everyone would work for nobody except
 * super admins, and would tell everyone else their access had been
 * revoked. Hiding it is the repo's existing rule for destructive
 * controls, set by the promote/demote toggle.
 */
import { AdminTierProvider } from '../_AdminTier';
import { HardDeleteButton } from '../_HardDeleteButton';
import { TypeToConfirm } from '../_TypeToConfirm';
import { AdminError, deleteErrorCopy } from '../../../lib/admin/shared';

function renderAsTier(isSuperAdmin: boolean, ui: React.ReactNode) {
  return render(<AdminTierProvider isSuperAdmin={isSuperAdmin}>{ui}</AdminTierProvider>);
}

describe('HardDeleteButton', () => {
  const props = { onDelete: vi.fn(), onDeleted: vi.fn(), testId: 'x-delete' };

  it('renders nothing for a plain admin', () => {
    renderAsTier(false, <HardDeleteButton {...props} />);

    expect(screen.queryByTestId('x-delete')).toBeNull();
  });

  // Absent provider = absent tier. A page rendered outside the admin
  // layout must not offer a control the server will refuse.
  it('renders nothing when the tier is unknown', () => {
    render(<HardDeleteButton {...props} />);

    expect(screen.queryByTestId('x-delete')).toBeNull();
  });

  it('deletes for a super admin, but only after the second click', async () => {
    const onDelete = vi.fn().mockResolvedValue({ id: 'r1', deleted: true });
    const onDeleted = vi.fn();
    renderAsTier(true, <HardDeleteButton {...props} onDelete={onDelete} onDeleted={onDeleted} />);

    fireEvent.click(screen.getByTestId('x-delete'));
    expect(onDelete).not.toHaveBeenCalled();

    fireEvent.click(screen.getByTestId('x-delete-confirm'));
    await waitFor(() => expect(onDeleted).toHaveBeenCalled());
  });

  // The row stays put on failure — dropping it would tell the operator
  // the delete worked.
  it('surfaces a refusal and does not drop the row', async () => {
    const onDeleted = vi.fn();
    const onDelete = vi.fn().mockRejectedValue(new AdminError('nope', 404));
    renderAsTier(true, <HardDeleteButton {...props} onDelete={onDelete} onDeleted={onDeleted} />);

    fireEvent.click(screen.getByTestId('x-delete'));
    fireEvent.click(screen.getByTestId('x-delete-confirm'));

    expect(await screen.findByTestId('x-delete-error')).toHaveTextContent(/already be gone/i);
    expect(onDeleted).not.toHaveBeenCalled();
  });

  // Relying on the row unmounting to clear `busy` leaves the button
  // stuck disabled forever whenever it does not — a refetch that errors
  // keeps the stale row mounted under the same key.
  it('recovers its own busy state when the caller keeps the row mounted', async () => {
    const onDelete = vi.fn().mockResolvedValue({ id: 'r1', deleted: true });
    renderAsTier(true, <HardDeleteButton {...props} onDelete={onDelete} onDeleted={() => {}} />);

    fireEvent.click(screen.getByTestId('x-delete'));
    fireEvent.click(screen.getByTestId('x-delete-confirm'));

    await waitFor(() => expect(screen.getByTestId('x-delete')).toBeEnabled());
  });

  // The row's other actions have to go inert too, or a click lands on a
  // record already being destroyed.
  it('reports busy so sibling actions can disable themselves', async () => {
    const changes: boolean[] = [];
    renderAsTier(
      true,
      <HardDeleteButton
        {...props}
        onDelete={() => Promise.resolve({})}
        onDeleted={() => {}}
        onBusyChange={(b) => changes.push(b)}
      />,
    );

    fireEvent.click(screen.getByTestId('x-delete'));
    fireEvent.click(screen.getByTestId('x-delete-confirm'));

    await waitFor(() => expect(changes).toEqual([true, false]));
  });
});

describe('TypeToConfirm', () => {
  const props = {
    expected: 'Ninis Taqueria',
    label: 'Delete restaurant',
    onConfirm: vi.fn(),
    onCancel: vi.fn(),
    testId: 'tc',
  };

  it('keeps the button inert until the name matches', () => {
    render(<TypeToConfirm {...props} />);
    const confirm = screen.getByTestId('tc-confirm');

    expect(confirm).toBeDisabled();

    fireEvent.change(screen.getByTestId('tc-input'), { target: { value: 'Ninis' } });
    expect(confirm).toBeDisabled();

    fireEvent.change(screen.getByTestId('tc-input'), { target: { value: 'Ninis Taqueria' } });
    expect(confirm).toBeEnabled();
  });

  // The point is making the operator read which row they are on, not
  // testing their shift key.
  it('accepts a different case and surrounding whitespace', () => {
    render(<TypeToConfirm {...props} />);

    fireEvent.change(screen.getByTestId('tc-input'), { target: { value: '  ninis taqueria ' } });

    expect(screen.getByTestId('tc-confirm')).toBeEnabled();
  });
});

describe('deleteErrorCopy', () => {
  // A hard delete's 404 has two possible causes and the copy must not
  // assert either. The likely one is that the row is already gone
  // (`rescue_from RecordNotFound` answers 404); a tier refusal needs a
  // session whose tier went stale, because the control does not render
  // below super admin in the first place. Naming the tier — as this
  // first shipped — tells an operator who *has* the permission to go
  // hunting for it.
  it('does not blame the tier for a 404 it cannot attribute', () => {
    const err = new AdminError('nope', 404);

    const hard = deleteErrorCopy(err, { hard: true });
    expect(hard).toMatch(/already be gone/i);
    expect(hard).not.toMatch(/super admin/i);

    // A read's 404 keeps the shared wording — there it really does mean
    // the caller is no longer an admin.
    expect(deleteErrorCopy(err)).toMatch(/admin access is gone/i);
  });

  it('relays the endpoint a soft delete should have used', () => {
    const err = new AdminError('nope', 422, 'soft_delete_unsupported', {
      error: 'soft_delete_unsupported',
      use: 'POST /api/v1/admin/reviews/:id/hide with a reason',
    });

    expect(deleteErrorCopy(err)).toContain('POST /api/v1/admin/reviews/:id/hide');
  });

  it('names the two user refusals', () => {
    expect(deleteErrorCopy(new AdminError('x', 422, 'cannot_delete_self'))).toMatch(/your own/i);
    expect(deleteErrorCopy(new AdminError('x', 422, 'cannot_delete_super_admin'))).toMatch(
      /admin:revoke_super/,
    );
  });
});
