import { notFound } from 'next/navigation';
import Link from 'next/link';
import {
  fetchItem,
  fetchRestaurant,
  type Restaurant,
  type RestaurantItem,
} from '../../../../../lib/restaurants';
import { fetchReviewsServer, type ReviewsResponse } from '../../../../../lib/reviews';
import { getServerJwt, getServerUserId } from '../../../../../lib/server-auth';
import FavoriteDishButton from './_FavoriteDishButton';
import DetectedIngredients from './_DetectedIngredients';
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
type Search = { profile?: string | string[] };

export default async function ItemDetailPage({
  params,
  searchParams,
}: {
  params: Promise<Params>;
  searchParams: Promise<Search>;
}) {
  const { slug, id } = await params;
  // Carried from the menu page's item links so the back-link can return
  // to the same filtered view instead of silently unfiltering.
  const { profile } = await searchParams;
  const presetSlug = (Array.isArray(profile) ? profile[0] : profile) ?? null;

  // The JWT lets fetchItem populate `favorited` for the save button;
  // anonymous callers still render (favorited defaults false, button hidden).
  const jwt = await getServerJwt();
  const [restaurant, item, initialReviews, currentUserId] = await Promise.all([
    fetchRestaurant(slug).catch(() => null),
    fetchItem(slug, id, { jwt: jwt ?? undefined, presetSlug }).catch(() => null),
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
      presetSlug={presetSlug}
    />
  );
}

function Page({
  restaurant,
  item,
  initialReviews,
  currentUserId,
  presetSlug,
}: {
  restaurant: Restaurant;
  item: RestaurantItem;
  initialReviews: ReviewsResponse;
  currentUserId: string | null;
  presetSlug: string | null;
}) {
  return (
    <main className="mx-auto max-w-3xl px-bw-6 py-bw-12">
      <p className="text-bite text-bw-sm font-semibold uppercase tracking-wider">
        <Link
          href={`/restaurants/${restaurant.slug}${presetSlug ? `?profile=${encodeURIComponent(presetSlug)}` : ''}`}
          className="hover:underline"
        >
          ← {restaurant.name}
        </Link>
      </p>
      <h1 className="mt-bw-2 text-bw-3xl font-bold">{item.name}</h1>
      {item.description && <p className="mt-bw-2 text-bw-base text-zinc-700">{item.description}</p>}

      {currentUserId && (
        <div className="mt-bw-4">
          <FavoriteDishButton itemId={item.id} initialFavorited={item.favorited ?? false} />
        </div>
      )}

      <DetectedIngredients
        ingredients={item.detected_ingredients ?? []}
        tags={item.detected_tags ?? []}
      />

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
