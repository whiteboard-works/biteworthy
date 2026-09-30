import { notFound, permanentRedirect } from 'next/navigation';
import type { Route } from 'next';
import { fetchRestaurant } from '../../../lib/restaurants';
import { edgeHeaders } from '../../../lib/edge-headers';
import { toQueryString } from '../../../lib/query-string';

/**
 * Location-based URLs — old flat restaurant URL: `/restaurants/<slug>`.
 *
 * `country` here is not a country — it's the old URL's slug segment. Next
 * routes any path this shallow to this handler because the new tree's
 * restaurant page lives 4 segments deep
 * (`/restaurants/[country]/[region]/[city]/[slug]`), so a 1-segment path
 * never reaches it. Look the restaurant up by slug and 301 to its real
 * `web_path`, preserving the query string (share tokens, diet presets).
 *
 * A failed fetch (unknown slug, or a draft the public endpoint 404s)
 * just 404s — there's nothing to redirect to.
 */
type Params = { country: string };
type Search = Record<string, string | string[] | undefined>;

export default async function OldRestaurantUrl({
  params,
  searchParams,
}: {
  params: Promise<Params>;
  searchParams: Promise<Search>;
}) {
  const { country: slug } = await params;
  const search = await searchParams;

  const restaurant = await fetchRestaurant(slug, { edgeHeaders: await edgeHeaders() }).catch(
    () => null,
  );
  if (!restaurant) notFound();

  permanentRedirect(`${restaurant.web_path}${toQueryString(search)}` as Route);
}
