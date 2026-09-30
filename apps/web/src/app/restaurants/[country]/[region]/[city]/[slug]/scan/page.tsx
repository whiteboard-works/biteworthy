import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { permanentRedirect, redirect } from 'next/navigation';
import type { Route } from 'next';
import { fetchRestaurant } from '../../../../../../../lib/restaurants';
import { getServerJwt } from '../../../../../../../lib/server-auth';
import { edgeHeaders } from '../../../../../../../lib/edge-headers';
import { isCanonicalPath, restaurantBasePath } from '../../../../../../../lib/restaurant-path';
import { ScanClient } from './_ScanClient';

export const metadata: Metadata = {
  title: 'Add a menu — BiteWorthy',
  robots: { index: false, follow: false },
};

type Params = { country: string; region: string; city: string; slug: string };

export default async function ScanPage({
  params,
  searchParams,
}: {
  params: Promise<Params>;
  searchParams: Promise<{ scan?: string | string[] }>;
}): Promise<ReactElement> {
  const { country, region, city, slug } = await params;
  // Built from the route params, not from a fetched restaurant — a draft
  // restaurant (below) has no public fetch to fall back on, and this page
  // has to work from the URL alone either way.
  const basePath = restaurantBasePath({ country, region, city, slug });
  const { scan } = await searchParams;
  const resumeScanId = (Array.isArray(scan) ? scan[0] : scan) ?? null;
  const jwt = await getServerJwt();
  const here = `${basePath}/scan${resumeScanId ? `?scan=${encodeURIComponent(resumeScanId)}` : ''}`;
  if (!jwt) redirect(`/login?next=${encodeURIComponent(here)}`);

  // A draft restaurant (just created, nothing published yet) is not on the
  // public endpoint, but its creator can still scan it — the scan door
  // decides who may, so a missing header only costs the display name.
  const restaurant = await fetchRestaurant(slug, { jwt, edgeHeaders: await edgeHeaders() }).catch(
    () => null,
  );
  // A published restaurant knows its real location; a stale one in the URL
  // would otherwise leak into every self-link the scan screen builds.
  if (restaurant && !isCanonicalPath(restaurant.web_path, { country, region, city, slug })) {
    const qs = resumeScanId ? `?scan=${encodeURIComponent(resumeScanId)}` : '';
    permanentRedirect(`${restaurant.web_path}/scan${qs}` as Route);
  }
  return (
    <ScanClient
      slug={slug}
      basePath={basePath}
      restaurantName={restaurant?.name ?? slug}
      resumeScanId={resumeScanId}
    />
  );
}
