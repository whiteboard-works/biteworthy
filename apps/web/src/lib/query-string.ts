/**
 * Location-based URLs — the old flat restaurant URLs (`/restaurants/<slug>`,
 * `/restaurants/<slug>/scan`, …) now live at the shallow levels of the new
 * `/restaurants/[country]/[region]/[city]/[slug]/...` tree and redirect to
 * their canonical path. Every redirect has to carry the visitor's query
 * string along (a share token, a diet preset, a resumed scan id) or the
 * 301 silently drops it.
 */
import type { ReadonlyURLSearchParams } from 'next/navigation';

type SearchParams = Record<string, string | string[] | undefined>;

/** `{ p: 'abc', profile: undefined }` → `'?p=abc'`; empty input → `''`. */
export function toQueryString(searchParams: SearchParams): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(searchParams)) {
    if (value === undefined) continue;
    for (const v of Array.isArray(value) ? value : [value]) params.append(key, v);
  }
  const qs = params.toString();
  return qs ? `?${qs}` : '';
}

/** Client-side twin for `URLSearchParams`/`ReadonlyURLSearchParams` instances. */
export function queryStringFrom(searchParams: URLSearchParams | ReadonlyURLSearchParams): string {
  const qs = searchParams.toString();
  return qs ? `?${qs}` : '';
}
