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
 *
 * A day holds SEVERAL ranges, because a split shift (lunch 11–14,
 * dinner 17–21) is an ordinary restaurant week. Folding it into one
 * 11–21 row would tell a hungry user the kitchen is open through the
 * afternoon lull when it isn't.
 */

interface HourRange {
  opens: string;
  closes: string;
}

interface HourDraft {
  closed: boolean;
  ranges: HourRange[];
}

const EMPTY_RANGE: HourRange = { opens: '', closes: '' };

function draftFromPlace(place: AdminPlace | null): HourDraft[] {
  const byDay = new Map<number, HourRange[]>();
  for (const row of place?.hours ?? []) {
    if (row.day_of_week == null) continue;
    if (!row.opens_at && !row.closes_at) continue;
    const ranges = byDay.get(row.day_of_week) ?? [];
    ranges.push({ opens: row.opens_at ?? '', closes: row.closes_at ?? '' });
    byDay.set(row.day_of_week, ranges);
  }
  return DAY_NAMES.map((_, day) => {
    const ranges = byDay.get(day);
    // No timed row at all is closed, same as an explicit blank row.
    // Each closed day gets its OWN blank range — sharing one object
    // across all seven would let an in-place edit corrupt the rest.
    return ranges?.length
      ? { closed: false, ranges }
      : { closed: true, ranges: [{ ...EMPTY_RANGE }] };
  });
}

function hoursPayload(draft: HourDraft[]): HourRow[] {
  // Every day travels, so an un-ticked day the admin left blank still
  // arrives as an explicit "closed" rather than silently vanishing.
  return draft.flatMap((day, index) => {
    const closed = [{ day_of_week: index, opens_at: null, closes_at: null }];
    if (day.closed) return closed;

    // A range added and never filled in is noise, not an instruction.
    // Sending it beside a real range reads as "closed AND open", which
    // the server refuses — failing the ENTIRE week over an empty box
    // the admin only had to click "+ Split shift" to create. A half-
    // filled range is real input and travels.
    const filled = day.ranges.filter((range) => range.opens.trim() || range.closes.trim());
    if (filled.length === 0) return closed;

    return filled.map((range) => ({
      day_of_week: index,
      opens_at: range.opens.trim() || null,
      closes_at: range.closes.trim() || null,
    }));
  });
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
            <th scope="col">Hours</th>
            <th scope="col">Closed</th>
          </tr>
        </thead>
        <tbody>
          {DAY_NAMES.map((day, index) => {
            const row = hours[index]!;
            const editDay = (next: Partial<HourDraft>) =>
              setHours(hours.map((r, i) => (i === index ? { ...r, ...next } : r)));
            const editRange = (at: number, next: Partial<HourRange>) =>
              editDay({ ranges: row.ranges.map((r, i) => (i === at ? { ...r, ...next } : r)) });

            return (
              <tr
                key={day}
                data-testid={`hours-row-${index}`}
                className="border-t border-zinc-100 align-top"
              >
                <th scope="row" className="py-bw-2 text-left font-normal text-zinc-700">
                  {day}
                </th>
                <td className="py-bw-2">
                  <div className="space-y-bw-1">
                    {row.ranges.map((range, at) => (
                      <div key={at} className="flex items-center gap-bw-2">
                        {/* type=time emits exactly HH:MM, which is what
                            the server's TIME_OF_DAY regex accepts — so a
                            typo is impossible rather than a rejected
                            round-trip. */}
                        <input
                          type="time"
                          value={range.opens}
                          onChange={(e) => editRange(at, { opens: e.target.value })}
                          disabled={row.closed}
                          aria-label={`${day} opens at${at > 0 ? ` (range ${at + 1})` : ''}`}
                          data-testid={`hours-opens-${index}-${at}`}
                          className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-xs disabled:bg-zinc-100"
                        />
                        <span className="text-bw-xs text-zinc-400">to</span>
                        <input
                          type="time"
                          value={range.closes}
                          onChange={(e) => editRange(at, { closes: e.target.value })}
                          disabled={row.closed}
                          aria-label={`${day} closes at${at > 0 ? ` (range ${at + 1})` : ''}`}
                          data-testid={`hours-closes-${index}-${at}`}
                          className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 text-bw-xs disabled:bg-zinc-100"
                        />
                        {row.ranges.length > 1 && (
                          <button
                            type="button"
                            onClick={() =>
                              editDay({ ranges: row.ranges.filter((_, i) => i !== at) })
                            }
                            aria-label={`Remove ${day} range ${at + 1}`}
                            data-testid={`hours-range-remove-${index}-${at}`}
                            className="text-bw-xs font-bold text-zinc-400 hover:text-danger"
                          >
                            ×
                          </button>
                        )}
                      </div>
                    ))}
                    {!row.closed && (
                      <button
                        type="button"
                        onClick={() => editDay({ ranges: [...row.ranges, { ...EMPTY_RANGE }] })}
                        data-testid={`hours-range-add-${index}`}
                        className="text-bw-xs font-semibold text-zinc-600 underline hover:text-zinc-900"
                      >
                        + Split shift
                      </button>
                    )}
                  </div>
                </td>
                <td className="py-bw-2">
                  <input
                    type="checkbox"
                    checked={row.closed}
                    onChange={(e) => editDay({ closed: e.target.checked })}
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
