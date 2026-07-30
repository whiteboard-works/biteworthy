import type { Metadata } from 'next';
import { notFound, redirect } from 'next/navigation';
import { getServerJwt } from '../../lib/server-auth';
import { jwtIsAdmin } from '../../lib/admin-auth';
import { AdminNav } from './_AdminNav';

/**
 * Server-side shell + guard for every /admin page. Signed-out visitors
 * go to login; anyone we can't CONFIRM as admin (non-admin, API error,
 * API without /me yet) gets the site's standard 404, which never
 * advertises that the surface exists.
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
  const jwt = await getServerJwt();
  if (!jwt) redirect('/login?next=/admin');
  if (!(await jwtIsAdmin(jwt))) notFound();

  return (
    <div className="mx-auto max-w-5xl px-bw-6 py-bw-6" data-testid="admin-shell">
      <AdminNav />
      {children}
    </div>
  );
}
