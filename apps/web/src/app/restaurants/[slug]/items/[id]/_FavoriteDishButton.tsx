'use client';

import FavoriteButton from '../../_FavoriteButton';
import { setItemFavorite } from '../../../../../lib/restaurants';

/**
 * Client boundary for the dish-page save button. The page is a server
 * component, so it can't hand FavoriteButton an onToggle function
 * directly — functions don't cross the RSC boundary (doing so 500'd
 * the page for every signed-in viewer). This wrapper takes only
 * serializable props and binds the fetch itself.
 */
export default function FavoriteDishButton({
  itemId,
  initialFavorited,
}: {
  itemId: string;
  initialFavorited: boolean;
}) {
  return (
    <FavoriteButton
      initialFavorited={initialFavorited}
      onToggle={(next) => setItemFavorite(itemId, next)}
      savedLabel="Saved"
      unsavedLabel="Save this dish"
      testId="favorite-dish"
    />
  );
}
