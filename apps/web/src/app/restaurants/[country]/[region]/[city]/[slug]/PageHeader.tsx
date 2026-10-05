'use client';

import { useState } from 'react';
import type { Restaurant } from '../../../../../../lib/restaurants';
import { getOpenStatus, formatWeeklyHours } from '../../../../../../lib/hours';
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
 * Restaurant hours block with open/closed status and weekly grid.
 * Computes status in the restaurant's timezone, not the viewer's.
 */
function RestaurantHours({ restaurant }: { restaurant: Restaurant }) {
  const [showAllHours, setShowAllHours] = useState(false);

  if (!restaurant.hours || restaurant.hours.length === 0) {
    return null;
  }

  const openStatus = getOpenStatus(restaurant.hours, restaurant.time_zone);
  const weeklyHours = formatWeeklyHours(restaurant.hours);
  const { dayOfWeek: today } = getCurrentDay(restaurant.time_zone);

  return (
    <div className="mt-bw-4 rounded-bw-lg border border-zinc-200 bg-white p-bw-4">
      {openStatus && (
        <p
          className="text-bw-sm font-semibold"
          data-testid="restaurant-open-status"
        >
          {openStatus.isOpen ? (
            <span className="text-ok">
              Open now{openStatus.isClosingSoon && ' • Closes soon'}
              {!openStatus.isClosingSoon && openStatus.nextChange && ` • ${openStatus.nextChange}`}
            </span>
          ) : (
            <span className="text-zinc-600">
              Closed{openStatus.nextChange && ` • ${openStatus.nextChange}`}
            </span>
          )}
        </p>
      )}

      <button
        type="button"
        onClick={() => setShowAllHours(!showAllHours)}
        className="mt-bw-2 text-bw-xs text-bite font-semibold hover:underline"
        data-testid="toggle-hours"
      >
        {showAllHours ? 'Hide hours' : 'Show hours'}
      </button>

      {showAllHours && (
        <div className="mt-bw-3 space-y-bw-2 text-bw-sm" data-testid="weekly-hours">
          {weeklyHours.map((day) => (
            <div
              key={day.dayOfWeek}
              className={`flex justify-between ${day.dayOfWeek === today ? 'font-semibold text-bite' : 'text-zinc-700'}`}
              data-testid={`hours-day-${day.dayOfWeek}`}
            >
              <span>{day.day}</span>
              <span>
                {day.intervals ? (
                  day.intervals.map((interval, i) => (
                    <span key={i}>
                      {i > 0 && ', '}
                      {interval.opens} – {interval.closes}
                    </span>
                  ))
                ) : (
                  <span className="text-zinc-400">Closed</span>
                )}
              </span>
            </div>
          ))}
          <p className="mt-bw-3 text-bw-xs text-zinc-500">
            Hours can change — please check with the restaurant to confirm.
          </p>
        </div>
      )}
    </div>
  );
}

/** Get current day in the restaurant's timezone. */
function getCurrentDay(timeZone: string | null): { dayOfWeek: number } {
  const now = new Date();
  const tz = timeZone ?? undefined;

  try {
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: tz,
      weekday: 'short',
    });
    const dayName = formatter.formatToParts(now).find((p) => p.type === 'weekday')?.value;
    const dayMap: Record<string, number> = {
      Sun: 0,
      Mon: 1,
      Tue: 2,
      Wed: 3,
      Thu: 4,
      Fri: 5,
      Sat: 6,
    };
    return { dayOfWeek: dayMap[dayName ?? 'Sun'] ?? 0 };
  } catch {
    return { dayOfWeek: now.getDay() };
  }
}

/**
 * City/region kicker, name, contact line, hours, and (signed-in only) the
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
      <RestaurantHours restaurant={restaurant} />
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
