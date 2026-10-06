/**
 * Diner dish-photo submissions. Multipart create goes through the Next
 * proxy so the cookie JWT is attached; the API strips EXIF/GPS before
 * storing, and nothing is public until a moderator approves it.
 */
import { shrinkForUpload } from './shrink-image';
import { PHOTO_MAX_BYTES, friendlyPhotoError } from './photo-errors';

export class PhotoSubmissionError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'PhotoSubmissionError';
  }
}

export interface PhotoSubmissionPayload {
  id: string;
  item_id: string;
  status: 'pending' | 'approved' | 'rejected' | 'withdrawn' | 'approve_keep';
  rejection_reason: string | null;
  owns_rights: boolean;
  review_id: string | null;
  photo_url: string | null;
  credit_name: string;
  created_at: string;
  reviewed_at: string | null;
}

export async function submitDishPhoto(
  itemId: string,
  photo: File,
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<PhotoSubmissionPayload> {
  const { fetchImpl = fetch } = opts;
  const shrunk = await shrinkForUpload(photo);
  if (shrunk.size > PHOTO_MAX_BYTES) {
    throw new PhotoSubmissionError(413, friendlyPhotoError('too_large'));
  }

  const form = new FormData();
  form.append('photo', shrunk, shrunk.name);
  form.append('owns_rights', 'true');

  const res = await fetchImpl(`/api/items/${encodeURIComponent(itemId)}/photo_submissions`, {
    method: 'POST',
    credentials: 'same-origin',
    body: form,
  });
  if (res.status === 413) throw new PhotoSubmissionError(413, friendlyPhotoError('too_large'));
  if (!res.ok) throw await photoError(res);
  return (await res.json()) as PhotoSubmissionPayload;
}

async function photoError(res: Response): Promise<PhotoSubmissionError> {
  let body: { error?: string; message?: string } | null = null;
  try {
    body = (await res.json()) as { error?: string; message?: string };
  } catch {
    // ignore
  }
  return new PhotoSubmissionError(res.status, friendlyPhotoError(body?.error, body?.message));
}
