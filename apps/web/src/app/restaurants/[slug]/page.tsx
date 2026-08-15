import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { fetchRestaurant, fetchRestaurantItems } from '../../../lib/restaurants';
import { getServerJwt } from '../../../lib/server-auth';
import { resolveMenuItems } from './_resolve-items';
import { RestaurantClient } from './RestaurantClient';

/**
 * Phase 3.6 + 3.9 — server-rendered restaurant page.
 *
 * The slug-based URL (`/restaurants/cream-bean-berry-1`) is what the
 * Phase 5 SEO city pages link to. Both endpoints accept either UUID or
 * slug; the SSR fetch here uses the slug.
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
type Params = { slug: string };
type Search = { p?: string | string[]; profile?: string | string[] };

/** App Router hands repeated query params over as arrays — take the first. */
function first(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

// The diet pages link every restaurant as ?profile=<diet> — up to one
// crawlable URL variant per diet. The canonical collapses them all onto
// the bare menu page.
export async function generateMetadata({ params }: { params: Promise<Params> }): Promise<Metadata> {
  const { slug } = await params;
  return { alternates: { canonical: `/restaurants/${encodeURIComponent(slug)}` } };
}

export default async function RestaurantPage({
  params,
  searchParams,
}: {
  params: Promise<Params>;
  searchParams: Promise<Search>;
}) {
  const { slug } = await params;
  const search = await searchParams;
  const profileToken = first(search.p);
  const presetSlug = first(search.profile);

  // The JWT lets fetchRestaurant populate `favorited` for the save button;
  // its presence also gates the button (the endpoint is authed).
  const jwt = await getServerJwt();
  const fetchItems = (token: string | undefined, preset: string | undefined) =>
    fetchRestaurantItems(slug, { profileToken: token, presetSlug: preset, jwt: jwt ?? undefined });

  const restaurantPromise = fetchRestaurant(slug, { jwt: jwt ?? undefined }).catch(() => null);
  // Bad filter params fall back instead of 404ing a live page — the
  // chain (and why only 422/404 classify) lives in _resolve-items.ts.
  const {
    items: initialItems,
    shareTokenInvalid,
    presetInvalid,
  } = await resolveMenuItems(fetchItems, profileToken, presetSlug);
  const restaurant = await restaurantPromise;

  if (!restaurant || !initialItems) notFound();

  return (
    <RestaurantClient
      slug={slug}
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
