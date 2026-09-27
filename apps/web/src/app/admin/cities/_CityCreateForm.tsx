'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { createCity } from '../../../lib/cities';
import { AdminError, friendlyAdminError } from '../../../lib/admin/shared';

const EMPTY_FORM = { name: '', region: '' };

export function CityCreateForm() {
  const router = useRouter();
  const [form, setForm] = useState(EMPTY_FORM);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setCreating(true);
    setError(null);
    try {
      await createCity({ name: form.name.trim(), region: form.region.trim() });
      setForm(EMPTY_FORM);
      router.refresh();
    } catch (err) {
      setError(createCityErrorCopy(err));
    } finally {
      setCreating(false);
    }
  };

  return (
    <form
      onSubmit={(e) => void onCreate(e)}
      data-testid="city-create-form"
      className="mt-bw-4 grid gap-bw-2 rounded-bw-lg border border-zinc-200 bg-zinc-50 p-bw-3 text-bw-sm sm:grid-cols-3"
    >
      <input
        value={form.name}
        onChange={(e) => setForm({ ...form, name: e.target.value })}
        placeholder="City (Salt Lake City)"
        required
        data-testid="city-new-name"
        className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
      />
      <input
        value={form.region}
        onChange={(e) => setForm({ ...form, region: e.target.value })}
        placeholder="State (Utah or UT)"
        required
        data-testid="city-new-region"
        className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
      />
      <button
        type="submit"
        disabled={creating}
        data-testid="city-create"
        className="rounded-bw-md bg-bite px-bw-3 py-bw-1 font-semibold text-white disabled:opacity-50"
      >
        {creating ? 'Adding…' : 'Add city'}
      </button>
      {error && (
        <p data-testid="city-create-error" className="text-red-700 sm:col-span-3">
          {error}
        </p>
      )}
    </form>
  );
}

function createCityErrorCopy(err: unknown): string {
  if (err instanceof AdminError && err.code === 'city_exists') {
    const city = err.body?.city as { name?: string; slug?: string } | undefined;
    return `Already covered as ${city?.name ?? 'that city'} (${city?.slug ?? '?'}).`;
  }
  if (err instanceof AdminError && err.status === 422 && err.code) return err.code;
  return friendlyAdminError(err);
}
