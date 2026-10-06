'use client';

import { useEffect, useState, type ChangeEvent, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { PhotoSubmissionError, submitDishPhoto } from '../../../../../../../../lib/photo-submissions';

/**
 * Unobtrusive diner photo offer on the dish page. Signed-out visitors
 * bounce to login and come back here. The file input is `accept="image/*"`
 * with no `capture` attribute so a phone offers camera *and* library
 * (forcing `capture="environment"` hid the library — see 2026-10-01).
 */
export function DishPhotoOffer({
  itemId,
  returnPath,
  signedIn,
  startOpen = false,
}: {
  itemId: string;
  returnPath: string;
  signedIn: boolean;
  startOpen?: boolean;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(startOpen);
  const [photo, setPhoto] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [ownsRights, setOwnsRights] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!photo) {
      setPreview(null);
      return;
    }
    const url = URL.createObjectURL(photo);
    setPreview(url);
    return () => URL.revokeObjectURL(url);
  }, [photo]);

  const onPick = (e: ChangeEvent<HTMLInputElement>) => {
    setPhoto(e.target.files?.[0] ?? null);
    setSubmitted(false);
  };

  const onAddClick = () => {
    if (!signedIn) {
      router.replace(`/login?next=${encodeURIComponent(returnPath)}`);
      return;
    }
    setOpen(true);
  };

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!photo) {
      setError('Pick a photo first.');
      return;
    }
    if (!ownsRights) {
      setError('Please confirm you took this photo.');
      return;
    }
    try {
      setSubmitting(true);
      await submitDishPhoto(itemId, photo);
      setSubmitted(true);
      setPhoto(null);
      setOwnsRights(false);
    } catch (err) {
      if (err instanceof PhotoSubmissionError && err.status === 401) {
        router.replace(`/login?next=${encodeURIComponent(returnPath)}`);
        return;
      }
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  if (submitted) {
    return (
      <p className="mt-bw-4 text-bw-sm text-zinc-600" data-testid="photo-thanks">
        Thanks, a moderator will review it.
      </p>
    );
  }

  if (!open) {
    return (
      <p className="mt-bw-4">
        <button
          type="button"
          onClick={onAddClick}
          data-testid="add-dish-photo"
          className="text-bw-sm font-semibold text-bite hover:text-bite-dark"
        >
          Add a photo
        </button>
      </p>
    );
  }

  return (
    <form
      onSubmit={onSubmit}
      className="mt-bw-4 rounded-bw-md border border-zinc-200 p-bw-4"
      data-testid="dish-photo-form"
    >
      <p className="text-bw-sm font-semibold text-zinc-700">Add a photo of this dish</p>
      <p className="mt-1 text-bw-xs text-zinc-500">
        A moderator looks at it before it appears as the dish photo. Location data is
        stripped from the file.
      </p>
      <label className="mt-bw-3 block text-bw-sm font-semibold text-zinc-700">
        Photo
        <input
          type="file"
          accept="image/*"
          onChange={onPick}
          aria-label="dish-photo"
          className="mt-1 block w-full text-bw-sm"
        />
      </label>
      {preview && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={preview}
          alt="Preview of the photo you picked"
          data-testid="dish-photo-preview"
          className="mt-bw-3 max-h-64 w-full rounded-bw-md object-cover"
        />
      )}
      <label className="mt-bw-3 flex items-start gap-bw-2 text-bw-sm text-zinc-700">
        <input
          type="checkbox"
          checked={ownsRights}
          onChange={(e) => setOwnsRights(e.target.checked)}
          data-testid="owns-rights"
          className="mt-1"
        />
        <span>I took this photo and I&apos;m offering it as the dish photo.</span>
      </label>
      {error && (
        <p className="mt-bw-3 rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">
          {error}
        </p>
      )}
      <div className="mt-bw-3 flex items-center justify-end gap-bw-2">
        <button
          type="button"
          onClick={() => setOpen(false)}
          className="rounded-bw-md border border-zinc-200 bg-white px-bw-3 py-bw-2 text-bw-sm font-semibold text-zinc-700 hover:border-zinc-300"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={submitting}
          data-testid="submit-dish-photo"
          className={[
            'rounded-bw-md bg-bite px-bw-4 py-bw-2 text-bw-sm font-bold text-white',
            submitting ? 'opacity-60' : 'hover:bg-bite-dark',
          ].join(' ')}
        >
          {submitting ? 'Sending…' : 'Submit photo'}
        </button>
      </div>
    </form>
  );
}
