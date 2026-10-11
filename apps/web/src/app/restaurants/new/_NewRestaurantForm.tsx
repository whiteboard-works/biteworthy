'use client';

import { useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import type { Route } from 'next';
import {
  brandRestaurant,
  createRestaurant,
  type City,
  type DuplicateCandidate,
} from '../../../lib/cities';
import { NotSignedInError } from '../../../lib/chat';
import { MAX_UPLOAD_BYTES, shrinkForUpload, tooLargeToUpload } from '../../../lib/shrink-image';

const INPUT = 'mt-bw-1 w-full rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base';
const IMAGE_TYPES = 'image/jpeg,image/jpg,image/png,image/heic,image/heif,image/webp';

type ImageSlot = 'logo' | 'banner';

/**
 * One optional image for the new restaurant. The file is shrunk client
 * side before it is held, and previewed; it is uploaded only after the
 * restaurant exists, through the same branding door the owner uses.
 */
function ImageField({
  slot,
  label,
  hint,
  file,
  disabled,
  onChange,
  onError,
}: {
  slot: ImageSlot;
  label: string;
  hint: string;
  file: File | null;
  disabled: boolean;
  onChange: (file: File | null) => void;
  onError: (message: string | null) => void;
}) {
  const input = useRef<HTMLInputElement>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [processing, setProcessing] = useState(false);

  const replacePreview = (url: string | null) => {
    setPreview((old) => {
      if (old) URL.revokeObjectURL(old);
      return url;
    });
  };

  const pick = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const picked = e.target.files?.[0];
    if (!picked) return;
    onError(null);
    setProcessing(true);
    try {
      const shrunk = await shrinkForUpload(picked);
      if (tooLargeToUpload(shrunk)) {
        onError(`That image is still over ${MAX_UPLOAD_BYTES / (1024 * 1024)} MB after resizing.`);
        e.target.value = '';
        return;
      }
      replacePreview(URL.createObjectURL(shrunk));
      onChange(shrunk);
    } catch {
      onError('That image could not be processed. Try a different file.');
      e.target.value = '';
    } finally {
      setProcessing(false);
    }
  };

  const clear = () => {
    replacePreview(null);
    onChange(null);
    if (input.current) input.current.value = '';
  };

  // A HEIC the browser cannot decode comes back unshrunk; its preview
  // would be a broken image, so show the name instead.
  const undecodable = /image\/hei[cf]/i.test(file?.type ?? '');

  return (
    <div className="text-bw-sm">
      <p className="font-semibold text-zinc-800">
        {label} <span className="font-normal text-zinc-500">(optional)</span>
      </p>
      <p className="text-bw-xs text-zinc-500">{hint}</p>
      {file && preview ? (
        <div className="mt-bw-2 flex items-start gap-bw-3">
          {undecodable ? (
            <p
              className="rounded-bw-md bg-zinc-100 px-bw-3 py-bw-2 text-bw-xs text-zinc-600"
              data-testid={`new-restaurant-${slot}-preview`}
            >
              {file.name} selected (no preview for HEIC here; it is converted on save)
            </p>
          ) : (
            <img
              src={preview}
              alt={`${label} preview`}
              className={
                slot === 'logo'
                  ? 'h-20 w-20 rounded-bw-md object-cover'
                  : 'aspect-[8/3] w-full max-w-sm rounded-bw-md object-cover'
              }
              data-testid={`new-restaurant-${slot}-preview`}
            />
          )}
          <button
            type="button"
            onClick={clear}
            disabled={disabled}
            data-testid={`new-restaurant-${slot}-clear`}
            className="text-bw-xs font-semibold text-zinc-600 underline hover:text-zinc-900 disabled:opacity-50"
          >
            Remove
          </button>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => input.current?.click()}
          disabled={disabled || processing}
          data-testid={`new-restaurant-${slot}-upload`}
          className="mt-bw-2 text-bw-xs font-semibold text-bite underline hover:text-bite-dark disabled:opacity-50"
        >
          {processing ? 'Processing…' : `Add a ${slot}`}
        </button>
      )}
      <input
        ref={input}
        type="file"
        accept={IMAGE_TYPES}
        onChange={(e) => void pick(e)}
        className="hidden"
        data-testid={`new-restaurant-${slot}-input`}
      />
    </div>
  );
}

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
  const [logo, setLogo] = useState<File | null>(null);
  const [banner, setBanner] = useState<File | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // The restaurant exists but its images did not save: offer the scan
  // link rather than a retry, which would trip the duplicate check.
  const [brandingFailed, setBrandingFailed] = useState<{ scanPath: string } | null>(null);

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
      const scanPath = `${result.web_path}/scan`;
      if (logo || banner) {
        // Both images ride one request through the web server's body
        // cap; two files that each passed the check can fail together.
        try {
          if ((logo?.size ?? 0) + (banner?.size ?? 0) > MAX_UPLOAD_BYTES) {
            await brandRestaurant(result.slug, { logo });
            await brandRestaurant(result.slug, { banner });
          } else {
            await brandRestaurant(result.slug, { logo, banner });
          }
        } catch (err) {
          if (err instanceof NotSignedInError) throw err;
          setBrandingFailed({ scanPath });
          return;
        }
      }
      router.push(scanPath as Route);
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
          disabled={submitting}
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
          disabled={submitting}
          data-testid="new-restaurant-name"
          className={INPUT}
        />
      </label>
      <label className="block text-bw-sm font-semibold text-zinc-800">
        Street address <span className="font-normal text-zinc-500">(optional)</span>
        <input
          value={street}
          onChange={(e) => setStreet(e.target.value)}
          disabled={submitting}
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
          disabled={submitting}
          data-testid="new-restaurant-postal"
          className={INPUT}
        />
      </label>

      <ImageField
        slot="logo"
        label="Logo"
        hint="Square works best. Shown beside the name on cards and the page."
        file={logo}
        disabled={submitting}
        onChange={setLogo}
        onError={setError}
      />
      <ImageField
        slot="banner"
        label="Banner"
        hint="Wide (about 8:3). Runs across the top of the restaurant page."
        file={banner}
        disabled={submitting}
        onChange={setBanner}
        onError={setError}
      />

      {brandingFailed ? (
        <div
          data-testid="new-restaurant-branding-failed"
          className="rounded-bw-lg border border-amber-300 bg-amber-50 p-bw-4 text-bw-sm"
        >
          <p className="font-semibold text-zinc-900">
            The restaurant was added, but its images could not be saved.
          </p>
          <a
            href={brandingFailed.scanPath}
            data-testid="new-restaurant-continue"
            className="mt-bw-2 inline-block font-semibold text-bite hover:text-bite-dark"
          >
            Continue to scan the menu →
          </a>
        </div>
      ) : candidates ? (
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
