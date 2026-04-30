import { notFound } from 'next/navigation';
import {
  fetchRestaurant,
  fetchRestaurantItems,
} from '../../../lib/restaurants';
import { RestaurantClient } from './RestaurantClient';

/**
 * Phase 3.6 — server-rendered restaurant page.
 *
 * The slug-based URL (`/restaurants/cream-bean-berry-1`) is what the
 * Phase 5 SEO city pages will eventually link to. Both endpoints
 * accept either UUID or slug; the SSR fetch here uses the slug.
 *
 * The fetch is anonymous — Phase 4 brings cookie-session auth that
 * would let us pass the user's JWT here for profile-aware filtering
 * during SSR. For now the page renders with the server's "no filter"
 * default, then the client island lets the user pick a preset +
 * strictness for live re-filtering.
 */
type Params = { slug: string };

export default async function RestaurantPage({
  params,
}: {
  params: Promise<Params>;
}) {
  const { slug } = await params;

  const [restaurant, initialItems] = await Promise.all([
    fetchRestaurant(slug).catch(() => null),
    fetchRestaurantItems(slug).catch(() => null),
  ]);

  if (!restaurant || !initialItems) notFound();

  return <RestaurantClient slug={slug} restaurant={restaurant} initialItems={initialItems} />;
}
