/**
 * A phone photo is 3–8 MB and the API refuses a scan photo over 10 MB;
 * these pin that a big photo leaves the phone as a 2000px JPEG, and that
 * anything the manipulator cannot handle is sent as picked rather than
 * dropped.
 */
import { MAX_EDGE_PX, shrinkForUpload } from '../../lib/shrink-image';

const resize = jest.fn();
const release = jest.fn();
const saveAsync = jest.fn(async () => ({
  uri: 'file:///tmp/small.jpg',
  width: 2000,
  height: 1500,
}));
const renderAsync = jest.fn(async () => ({ saveAsync, release }));
const mockManipulate = jest.fn();

jest.mock('expo-image-manipulator', () => ({
  ImageManipulator: { manipulate: (uri: string) => mockManipulate(uri) },
  SaveFormat: { JPEG: 'jpeg' },
}));

const MB = 1024 * 1024;

beforeEach(() => {
  jest.clearAllMocks();
  const context = { resize, renderAsync, release };
  resize.mockReturnValue(context);
  mockManipulate.mockReturnValue(context);
});

it('sends a small photo as picked', async () => {
  const picked = {
    uri: 'file:///a.jpg',
    width: 1600,
    height: 1200,
    fileSize: MB,
    fileName: 'a.jpg',
    mimeType: 'image/jpeg',
  };

  await expect(shrinkForUpload(picked)).resolves.toEqual({
    uri: 'file:///a.jpg',
    name: 'a.jpg',
    type: 'image/jpeg',
  });
  expect(mockManipulate).not.toHaveBeenCalled();
});

it('shrinks a landscape photo to 2000px wide as a JPEG', async () => {
  const picked = { uri: 'file:///IMG_1.HEIC', width: 4032, height: 3024, fileSize: 6 * MB };

  await expect(shrinkForUpload(picked, 'menu.jpg')).resolves.toEqual({
    uri: 'file:///tmp/small.jpg',
    name: 'menu.jpg',
    type: 'image/jpeg',
  });
  expect(mockManipulate).toHaveBeenCalledWith('file:///IMG_1.HEIC');
  expect(resize).toHaveBeenCalledWith({ width: MAX_EDGE_PX });
  expect(saveAsync).toHaveBeenCalledWith({ compress: 0.85, format: 'jpeg' });
  expect(release).toHaveBeenCalledTimes(2);
});

it('shrinks a portrait photo by its height, keeping the picked name with a .jpg extension', async () => {
  const picked = {
    uri: 'file:///b.png',
    width: 3024,
    height: 4032,
    fileSize: 6 * MB,
    fileName: 'b.png',
  };

  await expect(shrinkForUpload(picked)).resolves.toMatchObject({
    name: 'b.jpg',
    type: 'image/jpeg',
  });
  expect(resize).toHaveBeenCalledWith({ height: MAX_EDGE_PX });
});

// Big bytes at a small size is a lossless or barely-compressed file; a
// re-encode is enough and a resize would only lose detail.
it('re-encodes without resizing a heavy photo already within the edge', async () => {
  await shrinkForUpload({ uri: 'file:///c.png', width: 1800, height: 1200, fileSize: 4 * MB });

  expect(mockManipulate).toHaveBeenCalled();
  expect(resize).not.toHaveBeenCalled();
});

it('treats an unknown size as large', async () => {
  await shrinkForUpload({ uri: 'file:///d.jpg' });

  expect(mockManipulate).toHaveBeenCalled();
  expect(resize).not.toHaveBeenCalled();
});

it('sends the picked file when the manipulator fails', async () => {
  renderAsync.mockRejectedValueOnce(new Error('no decoder'));
  const picked = {
    uri: 'file:///e.heic',
    width: 4032,
    height: 3024,
    fileSize: 6 * MB,
    mimeType: 'image/heic',
  };

  await expect(shrinkForUpload(picked)).resolves.toEqual({
    uri: 'file:///e.heic',
    name: 'photo.jpg',
    type: 'image/heic',
  });
});
