'use client';

import type { Restaurant } from '../../../lib/restaurants';
import FavoriteButton from './_FavoriteButton';

/**
 * Extracted from RestaurantClient (menu-page hierarchy pass) — the
 * restaurant name/city/contact block + save button, unchanged from
 * how RestaurantClient rendered it, just given its own file.
 */

/** Digits to dial: extensions ("ext 2", "x2", "#2") can't ride a tel: URI. */
function dialable(phone: string): string {
  return phone.split(/(?:ext|x|#)/i)[0]!.replace(/[^+\d]/g, '');
}

/** Scheme-less stored values ("www.x.com") must not resolve as relative URLs. */
function externalHref(website: string): string {
  return /^https?:\/\//i.test(website) ? website : `https://${website}`;
}

/**
 * Phone + website, already in the `#show` payload but never rendered —
 * the "confirm with the restaurant" disclaimer ends in a phone call, so
 * the page should hand over the number. Renders nothing when the data
 * is absent (most community-scanned restaurants at first).
 */
export function RestaurantContactLine({ restaurant }: { restaurant: Restaurant }) {
  if (!restaurant.phone && !restaurant.website) return null;
  return (
    <p className="mt-bw-2 flex flex-wrap gap-bw-4 text-bw-sm" data-testid="restaurant-contact">
      {restaurant.phone && (
        <a
          href={`tel:${dialable(restaurant.phone)}`}
          data-testid="restaurant-phone"
          className="font-semibold text-zinc-700 hover:text-bite-dark"
        >
          ☎ {restaurant.phone}
        </a>
      )}
      {restaurant.website && (
        <a
          href={externalHref(restaurant.website)}
          target="_blank"
          rel="noopener noreferrer"
          data-testid="restaurant-website"
          className="font-semibold text-zinc-700 hover:text-bite-dark"
        >
          Website ↗
        </a>
      )}
    </p>
  );
}

/**
 * City/region kicker, name, contact line, and (signed-in only) the
 * save-restaurant button — the page's top block, above the filter
 * controls.
 */
export function PageHeader({
  restaurant,
  signedIn,
  onToggleFavorite,
}: {
  restaurant: Restaurant;
  signedIn: boolean;
  onToggleFavorite: (next: boolean) => Promise<{ favorited: boolean }>;
}) {
  return (
    <>
      <p className="text-bite text-bw-sm font-semibold uppercase tracking-wider">
        {restaurant.city.name}, {restaurant.city.region}
      </p>
      <h1 className="mt-bw-2 text-bw-3xl font-bold">{restaurant.name}</h1>
      <RestaurantContactLine restaurant={restaurant} />
      {signedIn && (
        <div className="mt-bw-3">
          <FavoriteButton
            initialFavorited={restaurant.favorited ?? false}
            onToggle={onToggleFavorite}
            savedLabel="Saved"
            unsavedLabel="Save restaurant"
            testId="favorite-restaurant"
          />
        </div>
      )}
    </>
  );
}
