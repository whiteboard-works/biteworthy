import { redirect } from 'next/navigation';
import { ReactNode } from 'react';
import { getServerUserId } from '../../lib/server-auth';

/**
 * Server-side redirect for signed-in users visiting /login.
 *
 * Checks the bw_session cookie (via getServerUserId) and redirects to /
 * if already signed in, preventing the flash of the login form.
 *
 * Note: The layout cannot access searchParams, so the `next` redirect
 * param is handled by the client-side fallback in page.tsx if needed.
 * This server-side redirect eliminates the form flash for the common
 * case (signed-in user accidentally visits /login).
 */
export default async function LoginLayout({ children }: { children: ReactNode }) {
  const userId = await getServerUserId();
  
  if (userId) {
    redirect('/');
  }

  return <>{children}</>;
}
