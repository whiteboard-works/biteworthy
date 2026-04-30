import { notFound } from 'next/navigation';
import { fetchRestaurant, fetchRestaurantItems } from '../../../lib/restaurants';
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
 * The fetch is anonymous — Phase 4 brings cookie-session auth that
 * would let us pass the user's JWT here for profile-aware filtering
 * during SSR.
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

  const [restaurant, initialItems] = await Promise.all([
    fetchRestaurant(slug).catch(() => null),
    fetchRestaurantItems(slug, { profileToken }).catch(() => null),
  ]);

  if (!restaurant || !initialItems) notFound();

  return (
    <RestaurantClient
      slug={slug}
      restaurant={restaurant}
      initialItems={initialItems}
      profileToken={profileToken ?? null}
    />
  );
}
