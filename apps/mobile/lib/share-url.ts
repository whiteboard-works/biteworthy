/**
 * Phase 3.9 — build a shareable filter URL.
 *
 * The web app at `EXPO_PUBLIC_WEB_BASE` serves `/r/<slug>?p=<token>`;
 * a recipient opening the link sees the same hidden/visible split
 * without needing an account. The token is the same base64url
 * encoding the Rails controller decodes via `?profile_token=`.
 */
import { encodeProfileToken } from '@biteworthy/filter-engine';

export interface FilterForSharing {
  avoid_ingredient_ids: string[];
  avoid_tag_ids: string[];
  strictness: 'relaxed' | 'balanced' | 'strict';
}

export function buildShareUrl(
  slug: string,
  filter: FilterForSharing,
  baseUrl: string = process.env.EXPO_PUBLIC_WEB_BASE ?? 'http://localhost:3001',
): string {
  const token = encodeProfileToken({
    avoid_ingredient_ids: filter.avoid_ingredient_ids,
    avoid_tag_ids: filter.avoid_tag_ids,
    strictness: filter.strictness,
  });
  return `${baseUrl}/r/${encodeURIComponent(slug)}?p=${token}`;
}
