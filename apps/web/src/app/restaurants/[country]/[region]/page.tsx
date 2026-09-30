import type { Metadata, Route } from 'next';
import { notFound, permanentRedirect, redirect } from 'next/navigation';
import { fetchRestaurant } from '../../../../lib/restaurants';
import { getServerJwt } from '../../../../lib/server-auth';
import { edgeHeaders } from '../../../../lib/edge-headers';
import { toQueryString } from '../../../../lib/query-string';
import { pathSegment } from '../../../../lib/restaurant-path';
import { ScanClient } from './[city]/[slug]/scan/_ScanClient';
import { ClaimVerify } from './[city]/[slug]/claim/_ClaimVerify';

/**
 * Location-based URLs — old flat sub-page URL:
 * `/restaurants/<slug>/{scan|claim|suggestions}`.
 *
 * `country` is the old URL's slug segment, `region` is the sub-page name.
 * Anything else in `region` 404s — it isn't one of these three old
 * sub-pages. On a successful fetch, 301 to `<web_path>/<sub>` (query
 * string preserved).
 *
 * `scan` gets one exception: a draft restaurant is invisible to the
 * public show endpoint even for its own creator (published-only scope),
 * so a failed fetch there does NOT 404 — the scan screen renders
 * directly from the slug, exactly like the real scan page does. Its
 * self-links stay on this old-style URL (there's no web_path to redirect
 * to yet); once the restaurant publishes, this same handler's normal
 * fetch-and-redirect path takes over.
 *
 * `claim` likewise: a claim email sent before location URLs links here,
 * and the restaurant may have been unpublished since. The verify
 * endpoint doesn't require it to be public, so verify the token in
 * place rather than 404ing a still-valid credential.
 */
const SUB_PAGES = ['scan', 'claim', 'suggestions'] as const;
type SubPage = (typeof SUB_PAGES)[number];

function isSubPage(value: string): value is SubPage {
  return (SUB_PAGES as readonly string[]).includes(value);
}

type Params = { country: string; region: string };
type Search = Record<string, string | string[] | undefined>;

export const metadata: Metadata = {
  title: 'Add a menu — BiteWorthy',
  robots: { index: false, follow: false },
};

export default async function OldRestaurantSubPageUrl({
  params,
  searchParams,
}: {
  params: Promise<Params>;
  searchParams: Promise<Search>;
}) {
  const { country: slug, region } = await params;
  if (!isSubPage(region)) notFound();
  const search = await searchParams;

  const jwt = await getServerJwt();
  const edge = await edgeHeaders();
  const restaurant = await fetchRestaurant(slug, {
    jwt: jwt ?? undefined,
    edgeHeaders: edge,
  }).catch(() => null);

  if (restaurant) {
    permanentRedirect(`${restaurant.web_path}/${region}${toQueryString(search)}` as Route);
  }

  if (region === 'claim') {
    const t = search.t;
    return <ClaimVerify slug={slug} token={(Array.isArray(t) ? t[0] : t) ?? ''} />;
  }
  if (region !== 'scan') notFound();

  const scanParam = search.scan;
  const resumeScanId = (Array.isArray(scanParam) ? scanParam[0] : scanParam) ?? null;
  // Same gate as the real scan page: sign in before picking photos, not
  // after an upload 401s.
  if (!jwt) {
    const here = `/restaurants/${pathSegment(slug)}/scan${toQueryString(search)}`;
    redirect(`/login?next=${encodeURIComponent(here)}` as Route);
  }
  return (
    <ScanClient
      slug={slug}
      basePath={`/restaurants/${pathSegment(slug)}`}
      restaurantName={slug}
      resumeScanId={resumeScanId}
    />
  );
}
