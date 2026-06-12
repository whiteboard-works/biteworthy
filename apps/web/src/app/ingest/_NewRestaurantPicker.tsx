'use client';

import { useState, type FormEvent } from 'react';
import {
  createRestaurant,
  friendlyIngestionError,
  type CreatedRestaurant,
  type DuplicateCandidate,
} from '../../lib/ingestion';

/**
 * Phase 6.5 — the "which restaurant?" step of the community scan
 * flow. Create a new draft restaurant (with the Phase 6.2 dedup
 * guard rendered as "did you mean…?" cards) or pick one of the
 * suggested existing restaurants.
 *
 * Launch market is Durango; the city slug is a free input rather
 * than a select because there is no cities index endpoint yet (the
 * route is a Phase-0 stub — see routes.rb).
 */
export function NewRestaurantPicker({
  onPicked,
}: {
  onPicked: (restaurant: { id: string; name: string }) => void;
}) {
  const [name, setName] = useState('');
  const [citySlug, setCitySlug] = useState('durango');
  const [street, setStreet] = useState('');
  const [postalCode, setPostalCode] = useState('');
  const [candidates, setCandidates] = useState<DuplicateCandidate[] | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (force: boolean) => {
    setError(null);
    if (!name.trim()) {
      setError('Restaurant name is required.');
      return;
    }
    try {
      setSubmitting(true);
      const result = await createRestaurant({
        name: name.trim(),
        citySlug: citySlug.trim(),
        street: street.trim() || undefined,
        postalCode: postalCode.trim() || undefined,
        force,
      });
      if (result.kind === 'duplicates') {
        setCandidates(result.candidates);
        return;
      }
      setCandidates(null);
      onPicked(pickedShape(result.restaurant));
    } catch (e) {
      setError(friendlyIngestionError(e));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="space-y-3">
      <form
        onSubmit={(e: FormEvent) => {
          e.preventDefault();
          void submit(false);
        }}
        className="space-y-3"
      >
        <label className="block">
          <span className="text-sm font-medium text-zinc-700">Restaurant name</span>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Maria's Tacos"
            className="mt-1 w-full rounded border border-zinc-300 px-3 py-2"
          />
        </label>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <label className="block">
            <span className="text-sm font-medium text-zinc-700">City slug</span>
            <input
              type="text"
              value={citySlug}
              onChange={(e) => setCitySlug(e.target.value)}
              className="mt-1 w-full rounded border border-zinc-300 px-3 py-2"
            />
          </label>
          <label className="block">
            <span className="text-sm font-medium text-zinc-700">Street (optional)</span>
            <input
              type="text"
              value={street}
              onChange={(e) => setStreet(e.target.value)}
              placeholder="742 Main Ave"
              className="mt-1 w-full rounded border border-zinc-300 px-3 py-2"
            />
          </label>
          <label className="block">
            <span className="text-sm font-medium text-zinc-700">ZIP (optional)</span>
            <input
              type="text"
              value={postalCode}
              onChange={(e) => setPostalCode(e.target.value)}
              placeholder="81301"
              className="mt-1 w-full rounded border border-zinc-300 px-3 py-2"
            />
          </label>
        </div>
        <button
          type="submit"
          disabled={submitting}
          className="rounded bg-orange-600 px-4 py-2 font-semibold text-white disabled:opacity-50"
        >
          {submitting ? 'Checking…' : 'Create restaurant'}
        </button>
      </form>

      {error && (
        <div className="rounded border border-red-300 bg-red-50 p-3 text-sm text-red-900" role="alert">
          {error}
        </div>
      )}

      {candidates && candidates.length > 0 && (
        <div className="space-y-2 rounded-xl border border-amber-300 bg-amber-50 p-4" role="region" aria-label="possible duplicates">
          <p className="font-semibold text-amber-900">Did you mean one of these?</p>
          <ul className="space-y-2">
            {candidates.map((c) => (
              <li
                key={c.id}
                className="flex items-center justify-between rounded border border-amber-200 bg-white p-3"
              >
                <div>
                  <p className="font-medium">{c.name}</p>
                  <p className="text-sm text-zinc-600">
                    {c.street ?? 'No address on file'} · {c.status}
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => onPicked({ id: c.id, name: c.name })}
                  className="rounded border border-orange-600 px-3 py-1 text-sm font-semibold text-orange-700"
                >
                  Use this one
                </button>
              </li>
            ))}
          </ul>
          <button
            type="button"
            disabled={submitting}
            onClick={() => void submit(true)}
            className="text-sm font-semibold text-amber-900 underline"
          >
            None of these — create “{name}” anyway
          </button>
        </div>
      )}
    </div>
  );
}

function pickedShape(r: CreatedRestaurant): { id: string; name: string } {
  return { id: r.id, name: r.name };
}
