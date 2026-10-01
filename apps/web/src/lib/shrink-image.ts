/**
 * Phone photos are 3–8 MB, and every upload goes through a Vercel
 * function whose request body tops out at 4.5 MB — a full-size photo is
 * refused with a bare 413 before our code runs. Re-encoding to a 2000px
 * JPEG lands well under that, and loses nothing the menu reader needs:
 * vision models downscale anything larger anyway.
 */

/** Long edge after shrinking. */
export const MAX_EDGE_PX = 2000;
/** Below this, a photo is sent as picked. Also keeps a second pass a no-op. */
export const SHRINK_ABOVE_BYTES = 1.5 * 1024 * 1024;
/** Vercel's 4.5 MB body limit, less headroom for the multipart envelope. */
export const MAX_UPLOAD_BYTES = 4 * 1024 * 1024;

const JPEG_QUALITY = 0.85;

/**
 * Returns a smaller JPEG for a large photo, or the file untouched when it
 * is already small, is not an image (a PDF), or the browser can't decode
 * it — the upload then gets the size check's clear message instead.
 */
export async function shrinkForUpload(file: File): Promise<File> {
  if (!file.type.startsWith('image/') || file.size <= SHRINK_ABOVE_BYTES) return file;

  try {
    const image = await decode(file);
    const scale = Math.min(1, MAX_EDGE_PX / Math.max(image.width, image.height));
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(image.width * scale);
    canvas.height = Math.round(image.height * scale);
    const context = canvas.getContext('2d');
    if (!context) return file;
    context.drawImage(image.source, 0, 0, canvas.width, canvas.height);
    image.release();

    const blob = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, 'image/jpeg', JPEG_QUALITY),
    );
    if (!blob || blob.size >= file.size) return file;

    const name = file.name.replace(/\.[^.]+$/, '') + '.jpg';
    return new File([blob], name, { type: 'image/jpeg', lastModified: file.lastModified });
  } catch {
    return file;
  }
}

interface Decoded {
  source: CanvasImageSource;
  width: number;
  height: number;
  release: () => void;
}

/**
 * `createImageBitmap` first; an `<img>` when it refuses the format, since
 * Safari renders HEIC in an image element where some versions won't
 * decode it into a bitmap.
 */
async function decode(file: File): Promise<Decoded> {
  try {
    const bitmap = await createImageBitmap(file);
    return {
      source: bitmap,
      width: bitmap.width,
      height: bitmap.height,
      release: () => bitmap.close(),
    };
  } catch {
    const url = URL.createObjectURL(file);
    try {
      const img = new Image();
      img.src = url;
      await img.decode();
      return {
        source: img,
        width: img.naturalWidth,
        height: img.naturalHeight,
        release: () => URL.revokeObjectURL(url),
      };
    } catch (e) {
      URL.revokeObjectURL(url);
      throw e;
    }
  }
}

export function tooLargeToUpload(file: File): boolean {
  return file.size > MAX_UPLOAD_BYTES;
}

export const TOO_LARGE_MESSAGE =
  'That file is too large to upload (4 MB max). For a big PDF, send photos of the pages instead.';
