import { notFound, permanentRedirect } from 'next/navigation';
import type { Route } from 'next';
import { fetchRestaurant } from '../../../lib/restaurants';
import { edgeHeaders } from '../../../lib/edge-headers';
import { toQueryString } from '../../../lib/query-string';

/**
 * Phase 3.9 — short share-link route. `/r/<slug>?p=<token>` is the URL
 * the Share button generates, and mobile builds the same shape for its
 * own share links — both have to keep working with the query string.
 *
 * Location-based URLs — the restaurant page no longer lives at a plain
 * `/restaurants/<slug>`, so this can't re-export it directly anymore.
 * 301 to the real `web_path` instead, query string preserved (the share
 * token or diet preset). A failed fetch (unknown slug, or a draft the
 * public endpoint 404s) 404s — there's nothing to redirect to.
 */
type Params = { slug: string };
type Search = Record<string, string | string[] | undefined>;

export default async function ShareLinkRedirect({
  params,
  searchParams,
}: {
  params: Promise<Params>;
  searchParams: Promise<Search>;
}) {
  const { slug } = await params;
  const search = await searchParams;

  const restaurant = await fetchRestaurant(slug, { edgeHeaders: await edgeHeaders() }).catch(
    () => null,
  );
  if (!restaurant) notFound();

  permanentRedirect(`${restaurant.web_path}${toQueryString(search)}` as Route);
}
