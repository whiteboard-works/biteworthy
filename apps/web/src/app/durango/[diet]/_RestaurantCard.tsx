import type { ReactElement } from 'react';
import type { CityRanked } from '../../../lib/durango';

export function RestaurantCard({
  r,
  dietName,
  dietSlug,
}: {
  r: CityRanked['restaurants'][number];
  dietName: string;
  dietSlug: string;
}): ReactElement {
  const allHidden = r.visible_count === 0;
  return (
    <li
      data-testid={`restaurant-${r.slug}`}
      className={[
        'rounded-bw-lg border p-bw-4',
        allHidden ? 'border-zinc-200 bg-zinc-50' : 'border-zinc-200 bg-white shadow-sm',
      ].join(' ')}
    >
      {/* Carry the diet onto the menu page — the card's count only holds if
          the click-through applies the same preset. The count is for the
          diet alone (this page is cached, the same for everyone); a signed-in
          reader's own avoids are added on the menu, so it's labelled as the
          diet's count, not as "safe for you". */}
      <a
        href={`/restaurants/${encodeURIComponent(r.slug)}?profile=${encodeURIComponent(dietSlug)}`}
        className="block"
        data-testid={`restaurant-link-${r.slug}`}
      >
        <h2 className={['text-bw-lg font-bold', allHidden ? 'text-zinc-500' : 'text-zinc-900'].join(' ')}>
          {r.name}
        </h2>
        <p className="mt-bw-1 text-bw-sm text-zinc-600">
          {allHidden ? (
            <>No {dietName.toLowerCase()}-safe items in our index yet.</>
          ) : (
            <>
              <span className="font-semibold text-zinc-900">{r.visible_count}</span>{' '}
              {dietName.toLowerCase()}-friendly item
              {r.visible_count === 1 ? '' : 's'}{' '}
              <span className="text-zinc-500">· {r.hidden_count} hidden by your filter</span>
            </>
          )}
        </p>
      </a>
    </li>
  );
}
