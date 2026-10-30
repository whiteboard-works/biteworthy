import type { ReactElement } from 'react';

/**
 * Serialize structured data for a JSON-LD <script> tag.
 *
 * `JSON.stringify` alone is not safe inside HTML: a string containing
 * `</script>` would close the tag and let the rest of the payload run as
 * JS. Replacing `<` with its JSON unicode escape keeps `JSON.parse` of
 * the text identical while making the HTML parser ignore it.
 *
 * Matches the Next.js App Router JSON-LD guide (native <script>, not
 * next/script — JSON-LD is data, not executable JS).
 */
export function serializeJsonLd(data: unknown): string {
  return JSON.stringify(data).replace(/</g, '\\u003c');
}

export function JsonLd({ data }: { data: unknown }): ReactElement {
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: serializeJsonLd(data) }}
    />
  );
}

/** Origin with no trailing slash, for concatenating paths. */
export function jsonLdOrigin(siteUrl: string): string {
  return siteUrl.replace(/\/+$/, '');
}

export function restaurantItemListJsonLd({
  restaurants,
  siteUrl,
}: {
  restaurants: ReadonlyArray<{ name: string; web_path: string }>;
  siteUrl: string;
}): Record<string, unknown> {
  const origin = jsonLdOrigin(siteUrl);
  return {
    '@context': 'https://schema.org',
    '@type': 'ItemList',
    itemListElement: restaurants.map((r, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      item: {
        '@type': 'Restaurant',
        name: r.name,
        url: `${origin}${r.web_path}`,
      },
    })),
  };
}
