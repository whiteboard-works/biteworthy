'use client';

import { useEffect, useState } from 'react';
import {
  fetchAdminUsers,
  setUserAdmin,
  type AdminUserRow,
  type AdminUsersResponse,
} from '../../../lib/admin/management';
import { AdminError, friendlyAdminError } from '../../../lib/admin/shared';
import { ConfirmButton } from '../_ConfirmButton';
import { Pagination } from '../_Pagination';
import { StatusBadge } from '../_StatusBadge';

/**
 * /admin/users — search + the is_admin toggle. Promote/demote sit
 * behind the two-step confirm; the server's self-demotion refusal
 * surfaces as instructions (the system never reaches zero admins).
 */

const PAGE_SIZE = 25;

export default function AdminUsersPage() {
  const [q, setQ] = useState('');
  const [adminOnly, setAdminOnly] = useState(false);
  const [offset, setOffset] = useState(0);
  const [data, setData] = useState<AdminUsersResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setError(null);
    fetchAdminUsers({ q: q || undefined, adminOnly, limit: PAGE_SIZE, offset })
      .then((d) => {
        if (active) setData(d);
      })
      .catch((e: unknown) => {
        if (active) setError(friendlyAdminError(e));
      });
    return () => {
      active = false;
    };
  }, [q, adminOnly, offset]);

  const toggle = async (user: AdminUserRow) => {
    setBusyId(user.id);
    setError(null);
    try {
      const updated = await setUserAdmin(user.id, !user.is_admin);
      setData((prev) =>
        prev
          ? { ...prev, users: prev.users.map((u) => (u.id === updated.id ? { ...u, ...updated } : u)) }
          : prev,
      );
    } catch (e) {
      if (e instanceof AdminError && e.code === 'cannot_demote_self') {
        setError('You cannot demote yourself — ask another admin.');
      } else if (e instanceof AdminError && e.code === 'cannot_demote_super_admin') {
        // Without this branch the deliberate refusal renders as
        // friendlyAdminError's generic "Something went wrong loading
        // admin data", which reads as a bug rather than a rule.
        setError('Super admins are managed on the server — run admin:revoke_super first.');
      } else {
        setError(friendlyAdminError(e));
      }
    } finally {
      setBusyId((cur) => (cur === user.id ? null : cur));
    }
  };

  return (
    <main data-testid="admin-users">
      <h1 className="text-bw-2xl font-bold text-zinc-900">Users</h1>

      <div className="mt-bw-4 flex flex-wrap items-center gap-bw-4 text-bw-sm">
        <input
          value={q}
          onChange={(e) => {
            setQ(e.target.value);
            setOffset(0);
          }}
          placeholder="Search email, handle, name…"
          data-testid="users-search"
          className="rounded-bw-md border border-zinc-300 px-bw-3 py-bw-1"
        />
        <label className="flex items-center gap-bw-2 text-zinc-700">
          <input
            type="checkbox"
            checked={adminOnly}
            onChange={(e) => {
              setAdminOnly(e.target.checked);
              setOffset(0);
            }}
            data-testid="users-admin-filter"
          />
          Admins only
        </label>
      </div>

      {error && (
        <div role="alert" data-testid="users-error" className="mt-bw-4 rounded border border-red-300 bg-red-50 p-4 text-red-900">
          {error}
        </div>
      )}

      {!data && !error && (
        <p role="status" className="mt-bw-4 text-bw-sm text-zinc-500">
          Loading users…
        </p>
      )}

      {data && data.users.length === 0 && (
        <p data-testid="users-empty" className="mt-bw-6 text-bw-sm text-zinc-500">
          No users match.
        </p>
      )}

      {data && data.users.length > 0 && (
        <div className="mt-bw-4 space-y-bw-4">
          <ul className="space-y-bw-2">
            {data.users.map((user) => (
              <li
                key={user.id}
                data-testid={`user-row-${user.handle}`}
                className="flex flex-wrap items-center justify-between gap-bw-2 rounded-bw-lg border border-zinc-200 bg-white p-bw-3"
              >
                <div className="min-w-0">
                  <p className="font-semibold text-zinc-900">
                    {user.handle}
                    {user.is_admin && (
                      <span className="ml-bw-2 align-middle">
                        <StatusBadge
                          tone="bite"
                          label={user.is_super_admin ? 'super admin' : 'admin'}
                        />
                      </span>
                    )}
                  </p>
                  <p className="mt-bw-1 text-bw-xs text-zinc-500">
                    {user.email}
                    {user.display_name && <> · {user.display_name}</>} ·{' '}
                    {user.reviews_count ?? 0} reviews · {user.ingestion_runs_count ?? 0} scans
                  </p>
                </div>
                {/* A super admin's toggle is refused by the API, so the
                    control does not render at all — a button that always
                    fails is worse than no button. */}
                {user.is_super_admin ? (
                  <span className="text-bw-xs text-zinc-500">Managed on the server</span>
                ) : (
                  <ConfirmButton
                    label={user.is_admin ? 'Demote' : 'Promote to admin'}
                    busy={busyId === user.id}
                    disabled={busyId !== null && busyId !== user.id}
                    onConfirm={() => void toggle(user)}
                    testId={`user-toggle-${user.handle}`}
                  />
                )}
              </li>
            ))}
          </ul>
          <Pagination
            total={data.pagination.total}
            limit={data.pagination.limit}
            offset={data.pagination.offset}
            onOffset={setOffset}
          />
        </div>
      )}
    </main>
  );
}
