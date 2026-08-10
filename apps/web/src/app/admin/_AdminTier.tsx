'use client';

import { createContext, useContext } from 'react';

/**
 * Carries "is this session a super admin?" from the server layout (which
 * already calls `/me` for its guard) down to the client pages, so the
 * permanent-delete controls can be hidden from an admin who cannot use
 * them.
 *
 * **This is UI gating, not security** — the same disclaimer the layout
 * carries. Rails answers `?hard=true` from a non-super admin with a 404
 * whatever the browser renders. The point is the repo's existing rule
 * about destructive controls, set by the promote/demote toggle: a button
 * that always fails is worse than no button.
 *
 * Default false, so a page rendered outside the provider (a test, a
 * future route) hides the destructive controls rather than offering
 * them.
 */
const SuperAdminContext = createContext(false);

export function AdminTierProvider({
  isSuperAdmin,
  children,
}: {
  isSuperAdmin: boolean;
  children: React.ReactNode;
}) {
  return <SuperAdminContext.Provider value={isSuperAdmin}>{children}</SuperAdminContext.Provider>;
}

export function useIsSuperAdmin(): boolean {
  return useContext(SuperAdminContext);
}
