import type { Metadata } from 'next';
import type { ReactElement } from 'react';
import { redirect } from 'next/navigation';
import { fetchRestaurant } from '../../../../lib/restaurants';
import { getServerJwt } from '../../../../lib/server-auth';
import { ScanClient } from './_ScanClient';

export const metadata: Metadata = {
  title: 'Add a menu — BiteWorthy',
  robots: { index: false, follow: false },
};

type Params = { slug: string };

export default async function ScanPage({
  params,
  searchParams,
}: {
  params: Promise<Params>;
  searchParams: Promise<{ scan?: string | string[] }>;
}): Promise<ReactElement> {
  const { slug } = await params;
  const { scan } = await searchParams;
  const resumeScanId = (Array.isArray(scan) ? scan[0] : scan) ?? null;
  const jwt = await getServerJwt();
  const here = `/restaurants/${slug}/scan${resumeScanId ? `?scan=${encodeURIComponent(resumeScanId)}` : ''}`;
  if (!jwt) redirect(`/login?next=${encodeURIComponent(here)}`);

  // A draft restaurant (just created, nothing published yet) is not on the
  // public endpoint, but its creator can still scan it — the scan door
  // decides who may, so a missing header only costs the display name.
  const restaurant = await fetchRestaurant(slug, { jwt }).catch(() => null);
  return (
    <ScanClient
      slug={slug}
      restaurantName={restaurant?.name ?? slug}
      restaurantId={restaurant?.id ?? null}
      resumeScanId={resumeScanId}
    />
  );
}
