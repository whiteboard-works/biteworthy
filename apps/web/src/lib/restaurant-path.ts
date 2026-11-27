/**
 * Whether the URL a restaurant page was reached by is its canonical
 * `web_path`. Both sides are decoded first: the API percent-encodes the
 * slug, and route params may arrive encoded or not, so comparing raw
 * strings could redirect a page to itself forever.
 */
export function isCanonicalPath(
  webPath: string,
  params: { country: string; region: string; city: string; slug: string },
): boolean {
  const current = `/restaurants/${params.country}/${params.region}/${params.city}/${params.slug}`;
  return safeDecode(webPath) === safeDecode(current);
}

/**
 * How to send a visitor from this URL to `webPath`.
 *
 * `null` when the URL is already canonical. `temporary` (307) when only
 * the city segment is stale — city reassignment is a reversible admin
 * edit, and a cached 308 Ogden→Draper loops if the restaurant moves
 * back. `permanent` (308) for country/region/slug canonicalization.
 */
export function locationRedirectKind(
  webPath: string,
  params: { country: string; region: string; city: string; slug: string },
): 'temporary' | 'permanent' | null {
  if (isCanonicalPath(webPath, params)) return null;
  return cityOnlyMismatch(webPath, params) ? 'temporary' : 'permanent';
}

function cityOnlyMismatch(
  webPath: string,
  params: { country: string; region: string; city: string; slug: string },
): boolean {
  const canonical = restaurantSegments(safeDecode(webPath));
  const current = restaurantSegments(
    safeDecode(`/restaurants/${params.country}/${params.region}/${params.city}/${params.slug}`),
  );
  if (!canonical || !current) return false;
  return (
    canonical.country === current.country &&
    canonical.region === current.region &&
    canonical.slug === current.slug &&
    canonical.city !== current.city
  );
}

function restaurantSegments(
  path: string,
): { country: string; region: string; city: string; slug: string } | null {
  const parts = path.split('/').filter(Boolean);
  const country = parts[1];
  const region = parts[2];
  const city = parts[3];
  const slug = parts[4];
  if (parts[0] !== 'restaurants' || !country || !region || !city || !slug) return null;
  return { country, region, city, slug };
}

function safeDecode(path: string): string {
  try {
    return decodeURI(path)
      .split('/')
      .map((segment) => decodeURIComponent(segment))
      .join('/');
  } catch {
    return path;
  }
}

/**
 * A route param as a URL segment. Params may arrive encoded or decoded,
 * so decode first — encoding an already-encoded segment would turn
 * `%20` into `%2520`.
 */
export function pathSegment(param: string): string {
  let decoded = param;
  try {
    decoded = decodeURIComponent(param);
  } catch {
    // Malformed escape: encode the raw text as-is.
  }
  return encodeURIComponent(decoded);
}

/** `/restaurants/<country>/<region>/<city>/<slug>` from route params. */
export function restaurantBasePath(params: {
  country: string;
  region: string;
  city: string;
  slug: string;
}): string {
  return `/restaurants/${[params.country, params.region, params.city, params.slug]
    .map(pathSegment)
    .join('/')}`;
}
