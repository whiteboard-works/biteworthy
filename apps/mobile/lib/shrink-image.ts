/**
 * Mirrors `apps/web/src/lib/shrink-image.ts`. Phone photos are 3–8 MB;
 * the API refuses a scan photo over its 10 MB limit and stores a review
 * photo only under 5 MB. Re-encoding to a 2000px JPEG lands well under
 * both, and loses nothing the menu reader needs: vision models downscale
 * anything larger anyway.
 */
import { ImageManipulator, SaveFormat } from 'expo-image-manipulator';

/** Long edge after shrinking. */
export const MAX_EDGE_PX = 2000;
/** Below this, and within the edge, a photo is sent as picked. */
export const SHRINK_ABOVE_BYTES = 1.5 * 1024 * 1024;

const JPEG_QUALITY = 0.85;

/** The fields of an `ImagePicker` asset this reads; all but `uri` are optional there. */
export interface PickedImage {
  uri: string;
  width?: number;
  height?: number;
  fileSize?: number | null;
  fileName?: string | null;
  mimeType?: string | null;
}

/** The shape React Native's FormData takes for a file. */
export interface UploadFile {
  uri: string;
  name: string;
  type: string;
}

/**
 * Returns a smaller JPEG for a large photo, or the picked file untouched
 * when it is already small, or when the resize fails — the upload then
 * gets the server's clear message instead.
 */
export async function shrinkForUpload(
  asset: PickedImage,
  fallbackName = 'photo.jpg',
): Promise<UploadFile> {
  const picked = {
    uri: asset.uri,
    name: asset.fileName ?? fallbackName,
    type: asset.mimeType ?? 'image/jpeg',
  };
  const width = asset.width ?? 0;
  const height = asset.height ?? 0;
  const longEdge = Math.max(width, height);
  // An unknown size is treated as large: a needless re-encode is cheap,
  // a refused upload is not.
  const bytes = asset.fileSize ?? Infinity;
  if (longEdge <= MAX_EDGE_PX && bytes <= SHRINK_ABOVE_BYTES) return picked;

  try {
    const context = ImageManipulator.manipulate(asset.uri);
    if (longEdge > MAX_EDGE_PX) {
      context.resize(width >= height ? { width: MAX_EDGE_PX } : { height: MAX_EDGE_PX });
    }
    const image = await context.renderAsync();
    const saved = await image.saveAsync({ compress: JPEG_QUALITY, format: SaveFormat.JPEG });
    image.release();
    context.release();
    return {
      uri: saved.uri,
      name: picked.name.replace(/\.[^.]+$/, '') + '.jpg',
      type: 'image/jpeg',
    };
  } catch {
    return picked;
  }
}
