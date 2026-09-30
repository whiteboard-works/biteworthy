import type { Metadata, Route } from 'next';
import { notFound, permanentRedirect } from 'next/navigation';
import { fetchRestaurant, fetchRestaurantItems } from '../../../../../../lib/restaurants';
import { getServerJwt } from '../../../../../../lib/server-auth';
import { edgeHeaders } from '../../../../../../lib/edge-headers';
import { toQueryString } from '../../../../../../lib/query-string';
import { isCanonicalPath } from '../../../../../../lib/restaurant-path';
import { resolveMenuItems } from './_resolve-items';
import { RestaurantClient } from './RestaurantClient';

/**
 * Phase 3.6 + 3.9 — server-rendered restaurant page.
 *
 * Location-based URLs — the public path is now
 * `/restaurants/<country>/<region>/<city>/<slug>` (`Restaurant#web_path`).
 * Lookup is ALWAYS by the trailing `slug`; `country`/`region`/`city` are
 * for humans/SEO. When they don't match the restaurant's real location
 * this page 301s to the canonical path (query string preserved) — but
 * only once the restaurant has actually been fetched. A failed fetch
 * (e.g. a draft, which the public show endpoint 404s) just falls through
 * to the existing `notFound()` below rather than attempting a redirect
 * with nothing to redirect to.
 *
 * `?p=<token>` (Phase 3.9) and `?profile=<preset>` (durango-card links)
 * are forwarded to the items endpoint; the client island keeps them on
 * every refetch. Rails owns precedence (token > preset > the caller's
 * saved profile).
 *
 * Both fetches carry the caller's JWT. The menu is filtered by who is
 * asking — avoid lists, strictness, never-hide overrides, and taste
 * scores all key off that header — so an anonymous items fetch for a
 * signed-in reader renders someone else's menu. A share token still
 * wins over the saved profile (`Menus::Filter.build` precedence), so
 * passing the JWT does not hijack a shared link.
 */
type Params = { country: string; region: string; city: string; slug: string };
type Search = { p?: string | string[]; profile?: string | string[] };

/** App Router hands repeated query params over as arrays — take the first. */
function first(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

// The diet pages link every restaurant as ?profile=<diet> — up to one
// crawlable URL variant per diet. The canonical collapses them all onto
// the bare menu page. Falls back to the given path when the restaurant
// can't be fetched (e.g. a draft) — there's no web_path to prefer yet.
export async function generateMetadata({ params }: { params: Promise<Params> }): Promise<Metadata> {
  const { country, region, city, slug } = await params;
  const restaurant = await fetchRestaurant(slug, { edgeHeaders: await edgeHeaders() }).catch(
    () => null,
  );
  const canonical =
    restaurant?.web_path ??
    `/restaurants/${encodeURIComponent(country)}/${encodeURIComponent(region)}/${encodeURIComponent(city)}/${encodeURIComponent(slug)}`;
  return { alternates: { canonical } };
}

export default async function RestaurantPage({
  params,
  searchParams,
}: {
  params: Promise<Params>;
  searchParams: Promise<Search>;
}) {
  const { country, region, city, slug } = await params;
  const search = await searchParams;
  const profileToken = first(search.p);
  const presetSlug = first(search.profile);

  // The JWT lets fetchRestaurant populate `favorited` for the save button;
  // its presence also gates the button (the endpoint is authed).
  const jwt = await getServerJwt();
  const edge = await edgeHeaders();
  const fetchItems = (token: string | undefined, preset: string | undefined) =>
    fetchRestaurantItems(slug, {
      profileToken: token,
      presetSlug: preset,
      jwt: jwt ?? undefined,
      edgeHeaders: edge,
    });

  const restaurantPromise = fetchRestaurant(slug, {
    jwt: jwt ?? undefined,
    edgeHeaders: edge,
  }).catch(() => null);
  // Bad filter params fall back instead of 404ing a live page — the
  // chain (and why only 422/404 classify) lives in _resolve-items.ts.
  const {
    items: initialItems,
    shareTokenInvalid,
    presetInvalid,
  } = await resolveMenuItems(fetchItems, profileToken, presetSlug);
  const restaurant = await restaurantPromise;

  if (!restaurant || !initialItems) notFound();

  // The restaurant was fetched — its web_path is now the authority on
  // country/region/city. A mismatch (stale link, hand-typed URL, a
  // restaurant that moved cities) 301s to the real one.
  if (!isCanonicalPath(restaurant.web_path, { country, region, city, slug })) {
    permanentRedirect(`${restaurant.web_path}${toQueryString(search)}` as Route);
  }

  return (
    <RestaurantClient
      slug={slug}
      basePath={restaurant.web_path}
      restaurant={restaurant}
      initialItems={initialItems}
      profileToken={shareTokenInvalid ? null : (profileToken ?? null)}
      presetSlug={presetInvalid ? null : (presetSlug ?? null)}
      presetInvalid={presetInvalid}
      shareTokenInvalid={shareTokenInvalid}
      signedIn={Boolean(jwt)}
    />
  );
}
