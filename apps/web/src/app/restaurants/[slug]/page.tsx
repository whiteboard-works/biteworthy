import { notFound } from 'next/navigation';
import { fetchRestaurant, fetchRestaurantItems } from '../../../lib/restaurants';
import { getServerJwt } from '../../../lib/server-auth';
import { RestaurantClient } from './RestaurantClient';

/**
 * Phase 3.6 + 3.9 — server-rendered restaurant page.
 *
 * The slug-based URL (`/restaurants/cream-bean-berry-1`) is what the
 * Phase 5 SEO city pages will eventually link to. Both endpoints
 * accept either UUID or slug; the SSR fetch here uses the slug.
 *
 * Phase 3.9 adds `?p=<token>` for shareable filter URLs. The same
 * token gets passed straight through to the items endpoint via
 * `?profile_token=`; the client island keeps using it on every
 * subsequent refetch.
 *
 * Both fetches carry the caller's JWT. The menu is filtered by who is
 * asking — avoid lists, strictness, never-hide overrides, and taste
 * scores all key off that header — so an anonymous items fetch for a
 * signed-in reader renders someone else's menu. A share token still
 * wins over the saved profile (`Menus::Filter.build` precedence), so
 * passing the JWT does not hijack a shared link.
 */
type Params = { slug: string };
type Search = { p?: string };

export default async function RestaurantPage({
  params,
  searchParams,
}: {
  params: Promise<Params>;
  searchParams: Promise<Search>;
}) {
  const { slug } = await params;
  const { p: profileToken } = await searchParams;

  // The JWT lets fetchRestaurant populate `favorited` for the save button;
  // its presence also gates the button (the endpoint is authed).
  const jwt = await getServerJwt();
  const [restaurant, initialItems] = await Promise.all([
    fetchRestaurant(slug, { jwt: jwt ?? undefined }).catch(() => null),
    fetchRestaurantItems(slug, { profileToken, jwt: jwt ?? undefined }).catch(() => null),
  ]);

  if (!restaurant || !initialItems) notFound();

  return (
    <RestaurantClient
      slug={slug}
      restaurant={restaurant}
      initialItems={initialItems}
      profileToken={profileToken ?? null}
      signedIn={Boolean(jwt)}
    />
  );
}
