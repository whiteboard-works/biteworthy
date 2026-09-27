'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { createRestaurant, type City, type DuplicateCandidate } from '../../../lib/cities';
import { NotSignedInError } from '../../../lib/chat';

const INPUT = 'mt-bw-1 w-full rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base';

export function NewRestaurantForm({
  cities,
  loadFailed = false,
}: {
  cities: City[];
  loadFailed?: boolean;
}) {
  const router = useRouter();
  const [citySlug, setCitySlug] = useState(cities.length === 1 ? cities[0]!.slug : '');
  const [name, setName] = useState('');
  const [street, setStreet] = useState('');
  const [postalCode, setPostalCode] = useState('');
  const [candidates, setCandidates] = useState<DuplicateCandidate[] | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (loadFailed) {
    return (
      <p data-testid="new-restaurant-load-failed" className="mt-bw-6 text-bw-sm text-red-700">
        We couldn&apos;t load the cities we cover. Refresh to try again.
      </p>
    );
  }

  if (cities.length === 0) {
    return (
      <p data-testid="new-restaurant-no-cities" className="mt-bw-6 text-bw-sm text-zinc-600">
        We don&apos;t cover any cities yet.
      </p>
    );
  }

  const submit = async (force: boolean) => {
    setSubmitting(true);
    setError(null);
    try {
      const result = await createRestaurant({
        name: name.trim(),
        city_slug: citySlug,
        street: street.trim() || undefined,
        postal_code: postalCode.trim() || undefined,
        force,
      });
      if (result.kind === 'duplicate') {
        setCandidates(result.candidates);
        return;
      }
      router.push(`/restaurants/${result.slug}/scan`);
    } catch (err) {
      if (err instanceof NotSignedInError) {
        router.push('/login?next=%2Frestaurants%2Fnew');
        return;
      }
      setError('Something went wrong adding that restaurant. Try again.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        void submit(false);
      }}
      data-testid="new-restaurant-form"
      className="mt-bw-6 space-y-bw-4"
    >
      <label className="block text-bw-sm font-semibold text-zinc-800">
        City
        <select
          value={citySlug}
          onChange={(e) => {
            setCitySlug(e.target.value);
            setCandidates(null);
          }}
          required
          data-testid="new-restaurant-city"
          className={INPUT}
        >
          <option value="" disabled>
            Pick a city
          </option>
          {cities.map((c) => (
            <option key={c.slug} value={c.slug}>
              {c.name}, {c.region}
            </option>
          ))}
        </select>
      </label>
      <label className="block text-bw-sm font-semibold text-zinc-800">
        Restaurant name
        <input
          value={name}
          onChange={(e) => {
            setName(e.target.value);
            setCandidates(null);
          }}
          required
          data-testid="new-restaurant-name"
          className={INPUT}
        />
      </label>
      <label className="block text-bw-sm font-semibold text-zinc-800">
        Street address <span className="font-normal text-zinc-500">(optional)</span>
        <input
          value={street}
          onChange={(e) => setStreet(e.target.value)}
          data-testid="new-restaurant-street"
          className={INPUT}
        />
      </label>
      <label className="block text-bw-sm font-semibold text-zinc-800">
        ZIP <span className="font-normal text-zinc-500">(optional)</span>
        <input
          value={postalCode}
          onChange={(e) => setPostalCode(e.target.value)}
          inputMode="numeric"
          data-testid="new-restaurant-postal"
          className={INPUT}
        />
      </label>

      {candidates ? (
        <div
          data-testid="new-restaurant-duplicates"
          className="rounded-bw-lg border border-amber-300 bg-amber-50 p-bw-4"
        >
          <p className="text-bw-sm font-semibold text-zinc-900">Is it one of these?</p>
          <ul className="mt-bw-2 space-y-bw-1 text-bw-sm">
            {candidates.map((c, i) => (
              <li key={c.id ?? `hidden-${i}`} data-testid="new-restaurant-candidate">
                {c.scannable && c.slug ? (
                  <a
                    href={
                      c.status === 'published'
                        ? `/restaurants/${c.slug}`
                        : `/restaurants/${c.slug}/scan`
                    }
                    className="font-semibold text-bite hover:text-bite-dark"
                  >
                    {c.name}
                  </a>
                ) : (
                  <span className="font-semibold text-zinc-900">{c.name}</span>
                )}
                {c.street && <span className="text-zinc-500"> · {c.street}</span>}
                {!c.scannable && (
                  <span className="text-zinc-500">
                    {c.status === 'draft'
                      ? ' · someone is already adding this one'
                      : ' · no longer listed'}
                  </span>
                )}
              </li>
            ))}
          </ul>
          <button
            type="button"
            disabled={submitting}
            onClick={() => void submit(true)}
            data-testid="new-restaurant-force"
            className="mt-bw-3 text-bw-sm font-semibold text-zinc-700 underline disabled:opacity-50"
          >
            None of these — add it anyway
          </button>
        </div>
      ) : (
        <button
          type="submit"
          disabled={submitting}
          data-testid="new-restaurant-submit"
          className="rounded-bw-md bg-bite px-bw-4 py-bw-2 font-semibold text-white disabled:opacity-50"
        >
          {submitting ? 'Adding…' : 'Add and scan the menu'}
        </button>
      )}
      {error && (
        <p data-testid="new-restaurant-error" className="text-bw-sm text-red-700">
          {error}
        </p>
      )}
    </form>
  );
}
