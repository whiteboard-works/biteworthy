'use client';

import { useEffect, useRef, useState, type ReactElement } from 'react';
import type { Restaurant } from '../lib/restaurants';
import { MAX_UPLOAD_BYTES, shrinkForUpload, tooLargeToUpload } from '../lib/shrink-image';

const MAX_MB = MAX_UPLOAD_BYTES / (1024 * 1024);
const TOO_LARGE = `That image is still over ${MAX_MB} MB after resizing. Try a smaller one.`;
// Both images ride one request through the web server's body cap, so
// two files that each pass the per-file check can fail together.
const TOO_LARGE_TOGETHER = `Together these are over ${MAX_MB} MB. Save the logo and banner one at a time.`;

/**
 * Whether the signed-in viewer may edit this restaurant's branding from
 * its page: only its verified owner. Admins use /admin instead. The API
 * enforces the same rule; this only decides whether the editor renders,
 * so an unclaimed restaurant (null owner) must never match an anonymous
 * viewer (null id).
 */
export function canEditBranding(
  viewerId: string | null,
  restaurant: Pick<Restaurant, 'claimed_by_user_id'>,
): boolean {
  return viewerId !== null && viewerId === restaurant.claimed_by_user_id;
}

/**
 * Logo + banner uploader for a restaurant. Rendered on the public
 * restaurant page for its verified owner and on the admin workbench;
 * both PATCH the same `/api/restaurants/<id>/branding` proxy, and the
 * API decides who may (owner or admin), so this component carries no
 * authorization of its own.
 *
 * Each image is picked, shrunk client-side (the API caps the stored
 * copy at 5 MB and re-encodes it), and previewed; nothing is sent until
 * Save. "Remove" marks an image for removal the same way.
 */

export interface BrandingUrls {
  logo_url: string | null;
  banner_url: string | null;
}

type Slot = 'logo' | 'banner';

interface SlotDraft {
  file: File | null;
  previewUrl: string | null;
  remove: boolean;
}

const SLOT_COPY: Record<Slot, { label: string; hint: string; previewClass: string }> = {
  logo: {
    label: 'Logo',
    hint: 'Square works best. Shown beside the name on cards and the page.',
    previewClass: 'h-20 w-20 rounded-bw-md object-cover',
  },
  banner: {
    label: 'Banner',
    hint: 'Wide (about 8:3). Runs across the top of the restaurant page.',
    previewClass: 'aspect-[8/3] w-full max-w-sm rounded-bw-md object-cover',
  },
};

function emptyDraft(): SlotDraft {
  return { file: null, previewUrl: null, remove: false };
}

/** The FormData the branding endpoint reads; only changed slots are sent. */
export function brandingFormData(drafts: Record<Slot, SlotDraft>): FormData {
  const form = new FormData();
  (['logo', 'banner'] as const).forEach((slot) => {
    const draft = drafts[slot];
    if (draft.remove) form.append(`remove_${slot}`, 'true');
    else if (draft.file) form.append(slot, draft.file);
  });
  return form;
}

function hasChanges(drafts: Record<Slot, SlotDraft>): boolean {
  return (['logo', 'banner'] as const).some((s) => drafts[s].file !== null || drafts[s].remove);
}

export function BrandingEditor({
  endpoint,
  current,
  onSaved,
  fetchImpl = fetch,
}: {
  /** The proxy path to PATCH, e.g. `/api/restaurants/<id or slug>/branding`. */
  endpoint: string;
  current: BrandingUrls;
  onSaved: (urls: BrandingUrls) => void;
  fetchImpl?: typeof fetch;
}): ReactElement {
  const [drafts, setDrafts] = useState<Record<Slot, SlotDraft>>({
    logo: emptyDraft(),
    banner: emptyDraft(),
  });
  const [processing, setProcessing] = useState<Slot | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const inputs = { logo: useRef<HTMLInputElement>(null), banner: useRef<HTMLInputElement>(null) };

  // Preview URLs hold the shrunk bytes until revoked; drop the old one
  // whenever a slot changes and all of them on unmount.
  const previews = useRef<Record<Slot, string | null>>({ logo: null, banner: null });
  const setPreview = (slot: Slot, url: string | null) => {
    const old = previews.current[slot];
    if (old) URL.revokeObjectURL(old);
    previews.current[slot] = url;
  };
  useEffect(() => () => (['logo', 'banner'] as const).forEach((s) => setPreview(s, null)), []);

  const clearInputs = () =>
    (['logo', 'banner'] as const).forEach((s) => {
      const input = inputs[s].current;
      if (input) input.value = '';
    });

  const pick = async (slot: Slot, e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setError(null);
    setProcessing(slot);
    try {
      // Shrink first: a 6 MB phone photo comes out well under the cap.
      const shrunk = await shrinkForUpload(file);
      if (tooLargeToUpload(shrunk)) {
        setError(TOO_LARGE);
        e.target.value = '';
        return;
      }
      const previewUrl = URL.createObjectURL(shrunk);
      setPreview(slot, previewUrl);
      setDrafts((d) => ({ ...d, [slot]: { file: shrunk, previewUrl, remove: false } }));
    } catch {
      setError('That image could not be processed. Try a different file.');
      e.target.value = '';
    } finally {
      setProcessing(null);
    }
  };

  const remove = (slot: Slot) => {
    setPreview(slot, null);
    setDrafts((d) => ({ ...d, [slot]: { file: null, previewUrl: null, remove: true } }));
    const input = inputs[slot].current;
    if (input) input.value = '';
  };

  const save = async () => {
    const total = (['logo', 'banner'] as const).reduce(
      (sum, s) => sum + (drafts[s].file?.size ?? 0),
      0,
    );
    if (total > MAX_UPLOAD_BYTES) {
      setError(TOO_LARGE_TOGETHER);
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const res = await fetchImpl(endpoint, { method: 'PATCH', body: brandingFormData(drafts) });
      if (!res.ok) {
        const body = (await res.json().catch(() => ({}))) as { error?: string };
        setError(
          res.status === 403
            ? 'Only the verified owner can change these images.'
            : (body.error ?? `Could not save the images (${res.status}).`),
        );
        return;
      }
      const saved = (await res.json()) as BrandingUrls;
      onSaved({ logo_url: saved.logo_url ?? null, banner_url: saved.banner_url ?? null });
      (['logo', 'banner'] as const).forEach((s) => setPreview(s, null));
      setDrafts({ logo: emptyDraft(), banner: emptyDraft() });
      clearInputs();
    } catch {
      setError('Could not reach the server. Check your connection and try again.');
    } finally {
      setSaving(false);
    }
  };

  const shownUrl = (slot: Slot): string | null => {
    const draft = drafts[slot];
    if (draft.file) return draft.previewUrl;
    if (draft.remove) return null;
    return current[`${slot}_url`];
  };
  // A browser that cannot decode HEIC gets the original back from the
  // shrink step; its <img> would be a broken glyph, so say what was
  // picked instead. The API converts it on upload either way.
  const undecodable = (slot: Slot): boolean =>
    /image\/hei[cf]/i.test(drafts[slot].file?.type ?? '');

  return (
    <div className="space-y-bw-4 text-bw-sm" data-testid="branding-editor">
      {(['logo', 'banner'] as const).map((slot) => {
        const url = shownUrl(slot);
        const busy = saving || processing !== null;
        return (
          <div key={slot}>
            <p className="font-semibold text-zinc-900">{SLOT_COPY[slot].label}</p>
            <p className="text-bw-xs text-zinc-500">{SLOT_COPY[slot].hint}</p>
            {url ? (
              <div className="mt-bw-2 flex items-start gap-bw-3">
                {undecodable(slot) ? (
                  <p
                    className="rounded-bw-md bg-zinc-100 px-bw-3 py-bw-2 text-bw-xs text-zinc-600"
                    data-testid={`branding-${slot}-preview`}
                  >
                    {drafts[slot].file?.name} selected (no preview for HEIC here; it is converted on
                    save)
                  </p>
                ) : (
                  <img
                    src={url}
                    alt={`${SLOT_COPY[slot].label} preview`}
                    className={SLOT_COPY[slot].previewClass}
                    data-testid={`branding-${slot}-preview`}
                  />
                )}
                <div className="flex flex-col gap-bw-1">
                  <button
                    type="button"
                    onClick={() => inputs[slot].current?.click()}
                    disabled={busy}
                    data-testid={`branding-${slot}-replace`}
                    className="text-bw-xs font-semibold text-zinc-600 underline hover:text-zinc-900 disabled:opacity-50"
                  >
                    Replace
                  </button>
                  <button
                    type="button"
                    onClick={() => remove(slot)}
                    disabled={busy}
                    data-testid={`branding-${slot}-remove`}
                    className="text-bw-xs font-semibold text-red-600 underline hover:text-red-900 disabled:opacity-50"
                  >
                    Remove
                  </button>
                </div>
              </div>
            ) : (
              <button
                type="button"
                onClick={() => inputs[slot].current?.click()}
                disabled={busy}
                data-testid={`branding-${slot}-upload`}
                className="mt-bw-2 text-bw-xs font-semibold text-bite underline hover:text-bite-dark disabled:opacity-50"
              >
                {processing === slot ? 'Processing…' : `Upload a ${slot}`}
              </button>
            )}
            <input
              ref={inputs[slot]}
              type="file"
              accept="image/jpeg,image/jpg,image/png,image/heic,image/heif,image/webp"
              onChange={(e) => void pick(slot, e)}
              className="hidden"
              data-testid={`branding-${slot}-input`}
            />
          </div>
        );
      })}

      {error && (
        <p role="alert" data-testid="branding-error" className="text-bw-xs text-red-700">
          {error}
        </p>
      )}

      <button
        type="button"
        onClick={() => void save()}
        disabled={saving || processing !== null || !hasChanges(drafts)}
        data-testid="branding-save"
        className="rounded-bw-md bg-bite px-bw-3 py-bw-1 font-semibold text-white disabled:opacity-50"
      >
        {saving ? 'Saving…' : 'Save images'}
      </button>
    </div>
  );
}
