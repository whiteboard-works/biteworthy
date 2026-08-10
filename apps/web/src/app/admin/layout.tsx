import type { Metadata } from 'next';
import { notFound, redirect } from 'next/navigation';
import { getServerJwt } from '../../lib/server-auth';
import { adminIdentity } from '../../lib/admin-auth';
import { AdminNav } from './_AdminNav';
import { AdminTierProvider } from './_AdminTier';

/**
 * Server-side shell + guard for every /admin page. Signed-out visitors
 * (no cookie, or a JWT Rails rejects with 401 — expired/revoked) go to
 * login; anyone else we can't CONFIRM as admin (non-admin, API error,
 * API without /me yet) gets the site's standard 404, which never
 * advertises that the surface exists. The login bounce flattens deep
 * paths to /admin (a layout can't read the request pathname) — fine
 * while the section is shallow; revisit if deep links start mattering.
 *
 * The guard is UX, not security: it re-runs on document requests and
 * server renders but NOT on soft navigations between /admin children,
 * so a mid-session demotion can leave a stale shell. That's fine —
 * every data request goes through /api/admin/* and Rails re-checks
 * is_admin per call; the pages surface the resulting failures.
 *
 * force-dynamic + noindex: admin markup must never be prerendered,
 * cached, or indexed.
 */
export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  robots: { index: false, follow: false },
};

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const { status, isSuperAdmin } = await adminIdentity(await getServerJwt());
  if (status === 'unauthenticated') redirect('/login?next=/admin');
  if (status !== 'admin') notFound();

  return (
    <div className="mx-auto max-w-5xl px-bw-6 py-bw-6" data-testid="admin-shell">
      <AdminNav />
      <AdminTierProvider isSuperAdmin={isSuperAdmin}>{children}</AdminTierProvider>
    </div>
  );
}
