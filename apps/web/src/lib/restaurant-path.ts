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
