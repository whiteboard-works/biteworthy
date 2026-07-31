'use client';

import { useEffect, useState } from 'react';
import {
  DAY_NAMES,
  fetchAdminPlace,
  saveAddress,
  saveHours,
  structureErrorCopy,
  type AdminPlace,
  type HourRow,
} from '../../../../lib/admin/structure';
import { friendlyAdminError } from '../../../../lib/admin/shared';

/**
 * Address and opening hours. Both save wholesale, matching the API —
 * hours especially: a per-day write could land half-applied and
 * advertise the wrong opening time, so the grid always submits the
 * full week. A day with the Closed box ticked sends null times, which
 * is exactly how the schema encodes "closed".
 */

interface HourDraft {
  closed: boolean;
  opens: string;
  closes: string;
}

function draftFromPlace(place: AdminPlace | null): HourDraft[] {
  const byDay = new Map<number, { opens_at?: string | null; closes_at?: string | null }>();
  for (const row of place?.hours ?? []) {
    if (row.day_of_week != null) byDay.set(row.day_of_week, row);
  }
  return DAY_NAMES.map((_, day) => {
    const row = byDay.get(day);
    return {
      // A day with no row at all is closed, same as one with no times.
      closed: !row || (!row.opens_at && !row.closes_at),
      opens: row?.opens_at ?? '',
      closes: row?.closes_at ?? '',
    };
  });
}

function hoursPayload(draft: HourDraft[]): HourRow[] {
  // Every day travels, including an open one left blank — dropping it
  // would send the admin's un-ticked day back as Closed on reload.
  return draft.map((row, day) => ({
    day_of_week: day,
    opens_at: row.closed ? null : row.opens.trim() || null,
    closes_at: row.closed ? null : row.closes.trim() || null,
  }));
}

export function PlaceEditor({ restaurantId }: { restaurantId: string }) {
  const [place, setPlace] = useState<AdminPlace | null>(null);
  const [hours, setHours] = useState<HourDraft[]>(draftFromPlace(null));
  const [address, setAddress] = useState({
    street: '',
    city: '',
    region: '',
    postal_code: '',
    country: '',
  });
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState<string | null>(null);
  const [busy, setBusy] = useState<'address' | 'hours' | null>(null);

  useEffect(() => {
    let active = true;
    fetchAdminPlace(restaurantId)
      .then((res) => {
        if (!active) return;
        setPlace(res);
        setHours(draftFromPlace(res));
        setAddress({
          street: res.address?.street ?? '',
          city: res.address?.city ?? '',
          region: res.address?.region ?? '',
          postal_code: res.address?.postal_code ?? '',
          country: res.address?.country ?? '',
        });
      })
      .catch((e: unknown) => {
        if (active) setError(friendlyAdminError(e));
      });
    return () => {
      active = false;
    };
  }, [restaurantId]);

  const submitAddress = async () => {
    setBusy('address');
    setError(null);
    setSaved(null);
    try {
      setPlace(await saveAddress(restaurantId, address));
      setSaved('Address saved.');
    } catch (e) {
      setError(structureErrorCopy(e) ?? friendlyAdminError(e));
    } finally {
      setBusy(null);
    }
  };

  const submitHours = async () => {
    setBusy('hours');
    setError(null);
    setSaved(null);
    try {
      const res = await saveHours(restaurantId, hoursPayload(hours));
      setPlace(res);
      setHours(draftFromPlace(res));
      setSaved('Hours saved.');
    } catch (e) {
      setError(structureErrorCopy(e) ?? friendlyAdminError(e));
    } finally {
      setBusy(null);
    }
  };

  return (
    <section
      data-testid="place-editor"
      aria-labelledby="place-heading"
      className="rounded-bw-lg border border-zinc-200 bg-white p-bw-4"
    >
      <h2 id="place-heading" className="text-bw-sm font-semibold text-zinc-600">
        Address &amp; hours
      </h2>

      {error && (
        <p role="alert" data-testid="place-error" className="mt-bw-2 text-bw-sm text-red-700">
          {error}
        </p>
      )}
      {saved && (
        <p role="status" data-testid="place-saved" className="mt-bw-2 text-bw-sm text-ok">
          {saved}
        </p>
      )}
      {!place && !error && (
        <p role="status" className="mt-bw-2 text-bw-sm text-zinc-500">
          Loading…
        </p>
      )}

      <div className="mt-bw-3 grid gap-bw-2 text-bw-sm sm:grid-cols-2">
        {(
          [
            ['street', 'Street'],
            ['city', 'City'],
            ['region', 'Region'],
            ['postal_code', 'Postal code'],
            ['country', 'Country'],
          ] as const
        ).map(([field, label]) => (
          <label key={field} className="flex flex-col gap-bw-1 text-zinc-600">
            {label}
            <input
              value={address[field]}
              onChange={(e) => setAddress({ ...address, [field]: e.target.value })}
              data-testid={`address-${field}`}
              className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
            />
          </label>
        ))}
        <div className="flex items-end justify-end sm:col-span-2">
          <button
            type="button"
            onClick={() => void submitAddress()}
            disabled={busy !== null || !place}
            data-testid="address-save"
            className="rounded-bw-md bg-bite px-bw-3 py-bw-1 text-bw-sm font-semibold text-white disabled:opacity-50"
          >
            {busy === 'address' ? 'Saving…' : 'Save address'}
          </button>
        </div>
      </div>

      <table className="mt-bw-4 w-full text-bw-sm" data-testid="hours-grid">
        <thead>
          <tr className="text-left text-bw-xs uppercase tracking-wide text-zinc-400">
            <th scope="col" className="py-bw-1">
              Day
            </th>
            <th scope="col">Opens</th>
            <th scope="col">Closes</th>
            <th scope="col">Closed</th>
          </tr>
        </thead>
        <tbody>
          {DAY_NAMES.map((day, index) => {
            const row = hours[index]!;
            return (
              <tr key={day} data-testid={`hours-row-${index}`} className="border-t border-zinc-100">
                <th scope="row" className="py-bw-1 text-left font-normal text-zinc-700">
                  {day}
                </th>
                <td>
                  <input
                    value={row.opens}
                    onChange={(e) =>
                      setHours(
                        hours.map((r, i) => (i === index ? { ...r, opens: e.target.value } : r)),
                      )
                    }
                    disabled={row.closed}
                    placeholder="11:00"
                    aria-label={`${day} opens at`}
                    data-testid={`hours-opens-${index}`}
                    className="w-20 rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-xs disabled:bg-zinc-100"
                  />
                </td>
                <td>
                  <input
                    value={row.closes}
                    onChange={(e) =>
                      setHours(
                        hours.map((r, i) => (i === index ? { ...r, closes: e.target.value } : r)),
                      )
                    }
                    disabled={row.closed}
                    placeholder="21:00"
                    aria-label={`${day} closes at`}
                    data-testid={`hours-closes-${index}`}
                    className="w-20 rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-xs disabled:bg-zinc-100"
                  />
                </td>
                <td>
                  <input
                    type="checkbox"
                    checked={row.closed}
                    onChange={(e) =>
                      setHours(
                        hours.map((r, i) => (i === index ? { ...r, closed: e.target.checked } : r)),
                      )
                    }
                    aria-label={`${day} closed`}
                    data-testid={`hours-closed-${index}`}
                  />
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>

      <div className="mt-bw-2 flex items-center justify-between">
        <p className="text-bw-xs text-zinc-500">
          Saving replaces the whole week — a half-applied save would advertise the wrong time.
        </p>
        <button
          type="button"
          onClick={() => void submitHours()}
          disabled={busy !== null || !place}
          data-testid="hours-save"
          className="rounded-bw-md bg-bite px-bw-3 py-bw-1 text-bw-sm font-semibold text-white disabled:opacity-50"
        >
          {busy === 'hours' ? 'Saving…' : 'Save hours'}
        </button>
      </div>
    </section>
  );
}
