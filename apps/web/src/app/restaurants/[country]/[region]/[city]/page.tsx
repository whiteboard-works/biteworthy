import { notFound, permanentRedirect } from 'next/navigation';
import type { Route } from 'next';
import { fetchRestaurant } from '../../../../../lib/restaurants';
import { edgeHeaders } from '../../../../../lib/edge-headers';
import { toQueryString } from '../../../../../lib/query-string';

/**
 * Location-based URLs — old flat item URL: `/restaurants/<slug>/items/<id>`.
 *
 * `country` is the old URL's slug segment, `region` must be the literal
 * `items`, and `city` is the item id. Anything else 404s. On a successful
 * fetch, 301 to `<web_path>/items/<id>` (query string preserved); a
 * failed fetch (unknown slug, or a draft the public endpoint 404s) 404s —
 * there's no restaurant to attach the item to either way.
 */
type Params = { country: string; region: string; city: string };
type Search = Record<string, string | string[] | undefined>;

export default async function OldRestaurantItemUrl({
  params,
  searchParams,
}: {
  params: Promise<Params>;
  searchParams: Promise<Search>;
}) {
  const { country: slug, region, city: itemId } = await params;
  if (region !== 'items') notFound();
  const search = await searchParams;

  const restaurant = await fetchRestaurant(slug, { edgeHeaders: await edgeHeaders() }).catch(
    () => null,
  );
  if (!restaurant) notFound();

  permanentRedirect(`${restaurant.web_path}/items/${itemId}${toQueryString(search)}` as Route);
}
