import { describe, expect, it } from 'vitest';
import { friendlyPhotoError } from '../photo-errors';

describe('friendlyPhotoError', () => {
  it('maps API codes to diner-facing copy, never the raw vips line', () => {
    expect(friendlyPhotoError('too_large')).toMatch(/under 4 MB/i);
    expect(friendlyPhotoError('too_many_pixels')).toMatch(/too big/i);
    expect(friendlyPhotoError('unprocessable_image')).toMatch(/could not read/i);
    expect(friendlyPhotoError('unsupported_type')).toMatch(/JPEG/i);
    expect(friendlyPhotoError('daily_limit')).toMatch(/10 dish photos today/i);
    expect(friendlyPhotoError('pending_limit')).toMatch(/3 photos of this dish/i);
    expect(friendlyPhotoError('owns_rights')).toMatch(/confirm you took this photo/i);
  });

  it('does not echo a libvips dump when the code is unknown', () => {
    expect(
      friendlyPhotoError('VipsForeignLoad: PNG read failed', 'Could not send that photo.'),
    ).toBe('Could not send that photo.');
  });
});
