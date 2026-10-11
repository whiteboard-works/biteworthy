import { redirect } from 'next/navigation';
import { ReactNode } from 'react';
import { getServerUserId } from '../../lib/server-auth';

/**
 * Server-side redirect for signed-in users visiting /signup.
 *
 * Checks the bw_session cookie (via getServerUserId) and redirects to
 * /restaurants if already signed in, preventing the ~0.45s flash of the
 * signup form that happens when relying only on the client-side check.
 *
 * The client-side check in page.tsx stays as a fallback for edge cases
 * where the cookie is set but the layout didn't redirect (e.g., client
 * navigation from a cached state).
 */
export default async function SignupLayout({ children }: { children: ReactNode }) {
  const userId = await getServerUserId();
  
  if (userId) {
    redirect('/restaurants');
  }

  return <>{children}</>;
}
