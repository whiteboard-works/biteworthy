import { notFound } from 'next/navigation';
import Link from 'next/link';
import {
  fetchItem,
  fetchRestaurant,
  type Restaurant,
  type RestaurantItem,
} from '../../../../../lib/restaurants';
import { fetchReviewsServer, type ReviewsResponse } from '../../../../../lib/reviews';
import { getServerUserId } from '../../../../../lib/server-auth';
import { ReviewsClient } from './ReviewsClient';
import { SuggestFixClient } from './SuggestFixClient';

/**
 * Phase 4.5 — server-rendered item detail page with reviews.
 *
 * URL is `/restaurants/<slug>/items/<id>` so search engines see the
 * full review text + photos for SEO. Initial reviews are fetched on
 * the server (anonymous public endpoint); the client island handles
 * the compose form + paginated load-more without re-rendering the
 * static parts.
 */
type Params = { slug: string; id: string };

export default async function ItemDetailPage({
  params,
}: {
  params: Promise<Params>;
}) {
  const { slug, id } = await params;

  const [restaurant, item, initialReviews, currentUserId] = await Promise.all([
    fetchRestaurant(slug).catch(() => null),
    fetchItem(slug, id).catch(() => null),
    fetchReviewsServer(id).catch(() => null),
    getServerUserId(),
  ]);

  if (!restaurant || !item) notFound();

  return (
    <Page
      restaurant={restaurant}
      item={item}
      initialReviews={initialReviews ?? emptyReviews(id)}
      currentUserId={currentUserId}
    />
  );
}

function Page({
  restaurant,
  item,
  initialReviews,
  currentUserId,
}: {
  restaurant: Restaurant;
  item: RestaurantItem;
  initialReviews: ReviewsResponse;
  currentUserId: string | null;
}) {
  return (
    <main className="mx-auto max-w-3xl px-bw-6 py-bw-12">
      <p className="text-bite text-bw-sm font-semibold uppercase tracking-wider">
        <Link href={`/restaurants/${restaurant.slug}`} className="hover:underline">
          ← {restaurant.name}
        </Link>
      </p>
      <h1 className="mt-bw-2 text-bw-3xl font-bold">{item.name}</h1>
      {item.description && (
        <p className="mt-bw-2 text-bw-base text-zinc-700">{item.description}</p>
      )}

      <ReviewsClient
        itemId={item.id}
        restaurantSlug={restaurant.slug}
        initial={initialReviews}
        currentUserId={currentUserId}
      />
      <SuggestFixClient itemId={item.id} restaurantSlug={restaurant.slug} />
    </main>
  );
}

function emptyReviews(itemId: string): ReviewsResponse {
  return { item_id: itemId, reviews: [], total: 0 };
}
