import { notFound, permanentRedirect, redirect } from 'next/navigation';
import Link from 'next/link';
import type { Route } from 'next';
import {
  fetchItem,
  fetchRestaurant,
  type Restaurant,
  type RestaurantItem,
  type Strictness,
} from '../../../../../../../../lib/restaurants';
import { fetchReviewsServer, type ReviewsResponse } from '../../../../../../../../lib/reviews';
import { getServerJwt, getServerUserId } from '../../../../../../../../lib/server-auth';
import { edgeHeaders } from '../../../../../../../../lib/edge-headers';
import { toQueryString } from '../../../../../../../../lib/query-string';
import { isCanonicalPath } from '../../../../../../../../lib/restaurant-path';
import FavoriteDishButton from './_FavoriteDishButton';
import DetectedIngredients from './_DetectedIngredients';
import { DishPhotoOffer } from './_DishPhotoOffer';
import { ReviewsClient } from './ReviewsClient';
import { SuggestFixClient } from './SuggestFixClient';

/**
 * Phase 4.5 — server-rendered item detail page with reviews.
 *
 * URL is `<web_path>/items/<id>` so search engines see the
 * full review text + photos for SEO. Initial reviews are fetched on
 * the server (anonymous public endpoint); the client island handles
 * the compose form + paginated load-more without re-rendering the
 * static parts.
 */
type Params = { country: string; region: string; city: string; slug: string; id: string };
type Search = { profile?: string | string[]; strictness?: string | string[]; addPhoto?: string | string[] };

const STRICTNESS: readonly Strictness[] = ['relaxed', 'balanced', 'strict'];
function parseStrictness(raw: string | string[] | undefined): Strictness | null {
  const value = Array.isArray(raw) ? raw[0] : raw;
  return STRICTNESS.find((s) => s === value) ?? null;
}

export default async function ItemDetailPage({
  params,
  searchParams,
}: {
  params: Promise<Params>;
  searchParams: Promise<Search>;
}) {
  const { country, region, city, slug, id } = await params;
  // Carried from the menu page's item links so the back-link can return
  // to the same filtered view instead of silently unfiltering.
  const search = await searchParams;
  const { profile, strictness: rawStrictness, addPhoto: rawAddPhoto } = search;
  const presetSlug = (Array.isArray(profile) ? profile[0] : profile) ?? null;
  const addPhoto = (Array.isArray(rawAddPhoto) ? rawAddPhoto[0] : rawAddPhoto) === '1';
  // The chat's results pane links here under the strictness the assistant
  // read the menu with; the server decides status under the same one.
  const strictness = parseStrictness(rawStrictness);

  // The JWT lets fetchItem populate `favorited` for the save button;
  // anonymous callers still render (favorited defaults false, button hidden).
  const jwt = await getServerJwt();
  const edge = await edgeHeaders();
  const [restaurant, item, initialReviews, currentUserId] = await Promise.all([
    fetchRestaurant(slug, { edgeHeaders: edge }).catch(() => null),
    fetchItem(slug, id, { jwt: jwt ?? undefined, presetSlug, strictness, edgeHeaders: edge }).catch(
      () => null,
    ),
    fetchReviewsServer(id, edge).catch(() => null),
    getServerUserId(),
  ]);

  if (!restaurant || !item) notFound();

  // Same rule as the menu page: a stale location in the URL 301s to the
  // canonical one, so a dish has one indexable address.
  if (!isCanonicalPath(restaurant.web_path, { country, region, city, slug })) {
    permanentRedirect(`${restaurant.web_path}/items/${id}${toQueryString(search)}` as Route);
  }

  if (addPhoto && currentUserId == null) {
    const next = `${restaurant.web_path}/items/${id}?addPhoto=1`;
    redirect(`/login?next=${encodeURIComponent(next)}` as Route);
  }

  return (
    <Page
      restaurant={restaurant}
      item={item}
      initialReviews={initialReviews ?? emptyReviews(id)}
      currentUserId={currentUserId}
      presetSlug={presetSlug}
      addPhoto={addPhoto}
    />
  );
}

function Page({
  restaurant,
  item,
  initialReviews,
  currentUserId,
  presetSlug,
  addPhoto,
}: {
  restaurant: Restaurant;
  item: RestaurantItem;
  initialReviews: ReviewsResponse;
  currentUserId: string | null;
  presetSlug: string | null;
  addPhoto: boolean;
}) {
  const photoSrc = item.photo_urls?.full || item.photo_url;
  return (
    <main className="mx-auto max-w-3xl px-bw-6 py-bw-12">
      <p className="text-bite text-bw-sm font-semibold uppercase tracking-wider">
        <Link
          href={
            `${restaurant.web_path}${presetSlug ? `?profile=${encodeURIComponent(presetSlug)}` : ''}` as Route
          }
          className="hover:underline"
        >
          ← {restaurant.name}
        </Link>
      </p>
      <h1 className="mt-bw-2 text-bw-3xl font-bold">{item.name}</h1>
      {item.description && <p className="mt-bw-2 text-bw-base text-zinc-700">{item.description}</p>}

      {photoSrc && (
        <figure className="mt-bw-4">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={photoSrc}
            alt={item.name}
            data-testid="dish-photo"
            className="max-h-[28rem] w-full rounded-bw-lg object-cover"
          />
          {item.photo_credit?.display_name && (
            <figcaption
              className="mt-bw-1 text-bw-xs text-zinc-500"
              data-testid="dish-photo-credit"
            >
              Photo by {item.photo_credit.display_name}
            </figcaption>
          )}
        </figure>
      )}

      {currentUserId && (
        <div className="mt-bw-4">
          <FavoriteDishButton itemId={item.id} initialFavorited={item.favorited ?? false} />
        </div>
      )}

      <DetectedIngredients
        ingredients={item.detected_ingredients ?? []}
        tags={item.detected_tags ?? []}
      />

      <DishPhotoOffer
        itemId={item.id}
        returnPath={`${restaurant.web_path}/items/${item.id}?addPhoto=1`}
        signedIn={currentUserId != null}
        startOpen={addPhoto}
        hasPhoto={Boolean(photoSrc)}
      />

      <ReviewsClient
        itemId={item.id}
        restaurantSlug={restaurant.slug}
        restaurantPath={restaurant.web_path}
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
