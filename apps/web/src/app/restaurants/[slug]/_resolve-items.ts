import { ApiError } from '../../../lib/api';
import type { RestaurantItemsResponse } from '../../../lib/restaurants';

export interface ResolvedMenu {
  items: RestaurantItemsResponse | null;
  shareTokenInvalid: boolean;
  presetInvalid: boolean;
}

/**
 * Fetch the menu, downgrading bad filter params instead of failing the
 * page: Rails 422s a malformed/expired share token and 404s an unknown
 * preset slug — neither may render "page not found" on a live
 * restaurant URL (share links get pasted around; diet links sit on
 * indexable SEO pages). Each offending param is dropped and the fetch
 * retried, worst case ending with neither.
 *
 * Deliberately narrow: only those two exact statuses classify. A
 * transient 429/500/network error resolves to `null` un-flagged — the
 * caller 404s rather than telling a user their valid link is broken.
 */
export async function resolveMenuItems(
  fetchItems: (
    token: string | undefined,
    preset: string | undefined,
  ) => Promise<RestaurantItemsResponse>,
  profileToken: string | undefined,
  presetSlug: string | undefined,
): Promise<ResolvedMenu> {
  let shareTokenInvalid = false;
  let presetInvalid = false;

  const classify = (e: unknown): null => {
    if (!(e instanceof ApiError)) return null;
    if (profileToken && !shareTokenInvalid && e.status === 422) {
      shareTokenInvalid = true;
    } else if (presetSlug && !presetInvalid && e.status === 404) {
      presetInvalid = true;
    }
    return null;
  };

  let items = await fetchItems(profileToken, presetSlug).catch(classify);
  if (!items && shareTokenInvalid) {
    items = await fetchItems(undefined, presetSlug).catch(classify);
  }
  if (!items && presetInvalid) {
    items = await fetchItems(shareTokenInvalid ? undefined : profileToken, undefined).catch(
      () => null,
    );
  }
  return { items, shareTokenInvalid, presetInvalid };
}
