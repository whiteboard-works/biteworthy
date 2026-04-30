import { notFound } from 'next/navigation';
import Link from 'next/link';
import { fetchPublicUserProfile, type UserReview } from '../../../lib/users';

/**
 * Phase 4.7 — public user profile at `/u/<handle>`.
 *
 * Server-rendered for SEO and so external links (e.g. shared review
 * cards) work even when the recipient isn't signed in. The endpoint
 * returns a public-only payload (no email, no dietary profile).
 *
 * Future Phase 4.X tabs (history, claimed restaurants) hang off the
 * same handle.
 */
type Params = { handle: string };

export default async function UserProfilePage({
  params,
}: {
  params: Promise<Params>;
}) {
  const { handle } = await params;
  const profile = await fetchPublicUserProfile(handle);
  if (!profile) notFound();

  const memberSince = new Date(profile.member_since).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
  });

  return (
    <main className="mx-auto max-w-3xl px-bw-6 py-bw-12">
      <p className="text-bite text-bw-sm font-semibold uppercase tracking-wider">Diner</p>
      <h1 className="mt-bw-2 text-bw-3xl font-bold">
        {profile.display_name ?? `@${profile.handle}`}
      </h1>
      <p className="mt-1 text-bw-sm text-zinc-500">@{profile.handle} · Member since {memberSince}</p>

      <dl className="mt-bw-4 grid grid-cols-2 gap-bw-3 sm:grid-cols-3">
        <Stat label="Reviews" value={profile.reviews_count} />
        <Stat label="Restaurants reviewed" value={profile.restaurants_reviewed_count} />
      </dl>

      <h2 className="mt-bw-6 text-bw-lg font-bold">Recent reviews</h2>
      <ul className="mt-bw-3 divide-y divide-zinc-100">
        {profile.recent_reviews.map((r) => (
          <ReviewRow key={r.id} review={r} />
        ))}
        {profile.recent_reviews.length === 0 && (
          <li className="py-bw-6 text-center text-bw-sm text-zinc-500">
            No reviews yet.
          </li>
        )}
      </ul>
    </main>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-bw-md border border-zinc-200 px-bw-3 py-bw-2">
      <dt className="text-bw-xs uppercase tracking-wider text-zinc-500">{label}</dt>
      <dd className="mt-1 text-bw-xl font-bold text-zinc-900">{value}</dd>
    </div>
  );
}

function ReviewRow({ review }: { review: UserReview }) {
  return (
    <li className="py-bw-3" data-testid={`review-${review.id}`}>
      <p className="text-bw-sm font-semibold text-zinc-700">
        <span className="text-bite">
          {'★'.repeat(review.rating)}
          <span className="text-zinc-300">{'☆'.repeat(5 - review.rating)}</span>
        </span>{' '}
        on{' '}
        <Link
          href={`/restaurants/${encodeURIComponent(review.item.restaurant.slug)}/items/${encodeURIComponent(review.item.id)}`}
          className="font-bold text-zinc-900 hover:text-bite-dark"
        >
          {review.item.name}
        </Link>{' '}
        <span className="text-zinc-500">at {review.item.restaurant.name}</span>
      </p>
      {review.body && <p className="mt-1 text-bw-base text-zinc-700">{review.body}</p>}
      {review.photo_url && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={review.photo_url}
          alt="Reviewer's photo"
          className="mt-bw-2 max-h-64 w-full rounded-bw-md object-cover"
        />
      )}
    </li>
  );
}
