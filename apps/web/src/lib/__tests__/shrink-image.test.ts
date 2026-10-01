import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MAX_EDGE_PX, MAX_UPLOAD_BYTES, shrinkForUpload, tooLargeToUpload } from '../shrink-image';

/**
 * A full-size phone photo is bigger than the 4.5 MB a Vercel function
 * accepts, so it was refused with a bare 413. These pin that a big photo
 * leaves the phone small enough to get through, and that anything we
 * can't safely re-encode is sent as picked rather than mangled.
 */

const MB = 1024 * 1024;

function fileOf(bytes: number, name: string, type: string): File {
  return new File([new Uint8Array(bytes)], name, { type });
}

let drawn: { width: number; height: number } | null;

// jsdom implements none of these; the spies below need something to wrap.
Object.assign(HTMLImageElement.prototype, { decode: async () => undefined });
Object.assign(URL, { createObjectURL: () => 'blob:menu', revokeObjectURL: () => undefined });

beforeEach(() => {
  drawn = null;
  vi.stubGlobal(
    'createImageBitmap',
    vi.fn(async () => ({ width: 4032, height: 3024, close: vi.fn() })),
  );
  vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(function (
    this: HTMLCanvasElement,
  ) {
    return {
      drawImage: () => {
        drawn = { width: this.width, height: this.height };
      },
    } as unknown as CanvasRenderingContext2D;
  } as unknown as HTMLCanvasElement['getContext']);
  vi.spyOn(HTMLCanvasElement.prototype, 'toBlob').mockImplementation((callback, type) =>
    callback(new Blob([new Uint8Array(600 * 1024)], { type: type ?? 'image/png' })),
  );
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('shrinkForUpload', () => {
  it('re-encodes a full-size phone photo to a JPEG under the upload limit', async () => {
    const photo = fileOf(6 * MB, 'IMG_0412.HEIC', 'image/heic');

    const out = await shrinkForUpload(photo);

    expect(out.type).toBe('image/jpeg');
    expect(out.name).toBe('IMG_0412.jpg');
    expect(tooLargeToUpload(out)).toBe(false);
    expect(drawn).toEqual({ width: MAX_EDGE_PX, height: 1500 });
  });

  it('sends a small photo as picked', async () => {
    const photo = fileOf(800 * 1024, 'menu.jpg', 'image/jpeg');

    expect(await shrinkForUpload(photo)).toBe(photo);
    expect(createImageBitmap).not.toHaveBeenCalled();
  });

  // A PDF can't be re-encoded; the size check gives it a clear message.
  it('leaves a PDF alone', async () => {
    const pdf = fileOf(6 * MB, 'menu.pdf', 'application/pdf');

    expect(await shrinkForUpload(pdf)).toBe(pdf);
  });

  // Some Safari versions refuse HEIC as a bitmap but render it in <img>.
  it('falls back to an image element when the bitmap decoder refuses the format', async () => {
    vi.mocked(createImageBitmap).mockRejectedValueOnce(new Error('unsupported'));
    vi.spyOn(HTMLImageElement.prototype, 'decode').mockResolvedValue(undefined);
    vi.spyOn(HTMLImageElement.prototype, 'naturalWidth', 'get').mockReturnValue(3024);
    vi.spyOn(HTMLImageElement.prototype, 'naturalHeight', 'get').mockReturnValue(4032);
    const photo = fileOf(6 * MB, 'menu.heic', 'image/heic');

    const out = await shrinkForUpload(photo);

    expect(out.type).toBe('image/jpeg');
    expect(drawn).toEqual({ width: 1500, height: MAX_EDGE_PX });
  });

  it('sends the original when the browser cannot decode it at all', async () => {
    vi.mocked(createImageBitmap).mockRejectedValueOnce(new Error('unsupported'));
    vi.spyOn(HTMLImageElement.prototype, 'decode').mockRejectedValue(new Error('unsupported'));
    const photo = fileOf(6 * MB, 'menu.heic', 'image/heic');

    expect(await shrinkForUpload(photo)).toBe(photo);
  });
});

describe('tooLargeToUpload', () => {
  it('flags anything over the limit', () => {
    expect(tooLargeToUpload(fileOf(MAX_UPLOAD_BYTES + 1, 'a.pdf', 'application/pdf'))).toBe(true);
    expect(tooLargeToUpload(fileOf(MAX_UPLOAD_BYTES, 'a.pdf', 'application/pdf'))).toBe(false);
  });
});
