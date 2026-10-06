/**
 * Friendly copy for diner photo-upload failures. The API returns a
 * short `error` code; never show raw libvips / UUID lines in the UI.
 */
export const PHOTO_MAX_BYTES = 5 * 1024 * 1024;

export const PHOTO_ERROR_COPY: Record<string, string> = {
  too_large: 'That photo is too large. Please pick a file under 5 MB.',
  too_many_pixels: 'That image is too big. Try a smaller photo of the dish.',
  unprocessable_image: 'We could not read that image. Try a JPEG or PNG photo of the dish.',
  unsupported_type: 'Please use a JPEG, PNG, WebP, or HEIC photo.',
  daily_limit: "You've submitted 10 dish photos today. Try again tomorrow.",
  pending_limit: 'You already have 3 photos of this dish waiting on a moderator.',
  owns_rights: 'Please confirm you took this photo.',
  photo_required: 'Pick a photo first.',
};

export function friendlyPhotoError(
  code: string | undefined,
  fallback = 'Could not send that photo. Try another image.',
): string {
  if (!code) return fallback;
  return PHOTO_ERROR_COPY[code] ?? fallback;
}
