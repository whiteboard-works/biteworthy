import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { Suspense } from 'react';
import { ConsentClient } from './_ConsentClient';

export const metadata: Metadata = {
  title: 'Connect an app — BiteWorthy',
  description: 'Review what an app is asking for before you connect it to your account.',
  // A one-off authorization screen, and one that carries a client's
  // parameters in the URL. Nothing here belongs in an index.
  robots: { index: false, follow: false },
};

/**
 * The OAuth consent screen.
 *
 * It lives in the web app rather than in Rails because this is the only
 * origin where a browser is signed in — the JWT is in an HttpOnly cookie
 * the API never receives. Rails' `/oauth/authorize` sends people here,
 * and approving sends them back with a short-lived token bound to the
 * exact request. See apps/api/config/initializers/doorkeeper.rb.
 */
export default function OauthConsentPage(): ReactElement {
  // useSearchParams needs a Suspense boundary or the production build
  // fails prerendering — same pattern as /login and /onboarding.
  return (
    <Suspense>
      <ConsentClient />
    </Suspense>
  );
}
