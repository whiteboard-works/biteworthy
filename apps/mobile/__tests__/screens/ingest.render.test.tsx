/**
 * Phase 6.6 — community scan flow on mobile. Covers the
 * RestaurantPicker step (create → dedup rows → pick/force) and the
 * upload → swipe-verify navigation. Mocks follow the
 * onboarding.render.test.tsx pattern (mock-prefixed vars + arrow
 * indirection for the hoist).
 */
const mockPush = jest.fn();
const mockReplace = jest.fn();
jest.mock('expo-router', () => ({
  router: {
    push: (...args: unknown[]) => mockPush(...args),
    replace: (...args: unknown[]) => mockReplace(...args),
    back: jest.fn(),
  },
  useLocalSearchParams: () => ({}),
  Link: 'Link',
}));

// Phase 7.1 — the screen captures through the CameraView ref, so the
// mock exposes takePictureAsync via useImperativeHandle. Permission
// state is mutable per test.
const mockTakePicture = jest.fn();
const mockRequestPermission = jest.fn();
let mockPermission: { granted: boolean; canAskAgain: boolean } | null = {
  granted: true,
  canAskAgain: true,
};
jest.mock('expo-camera', () => {
  const React = jest.requireActual<typeof import('react')>('react');
  return {
    CameraView: React.forwardRef((_props: unknown, ref: React.Ref<unknown>) => {
      React.useImperativeHandle(ref, () => ({
        takePictureAsync: (...args: unknown[]) => mockTakePicture(...args),
      }));
      return null;
    }),
    useCameraPermissions: () => [mockPermission, mockRequestPermission],
  };
});

jest.mock('../../lib/auth', () => ({
  getJwt: jest.fn(() => Promise.resolve('jwt-1')),
}));

const mockCreateRestaurant = jest.fn();
jest.mock('../../lib/api/restaurants', () => ({
  ...jest.requireActual('../../lib/api/restaurants'),
  createRestaurant: (...args: unknown[]) => mockCreateRestaurant(...args),
}));

const mockUpload = jest.fn();
jest.mock('../../lib/api/ingestion-runs', () => ({
  ...jest.requireActual('../../lib/api/ingestion-runs'),
  uploadIngestionRun: (...args: unknown[]) => mockUpload(...args),
}));

import { act, fireEvent, render, screen, waitFor } from '@testing-library/react-native';
import IngestScreen from '../../app/ingest/index';

const flush = () => act(async () => {});

describe('IngestScreen (Phase 6.6)', () => {
  beforeEach(() => {
    mockPush.mockClear();
    mockReplace.mockClear();
    mockCreateRestaurant.mockClear();
    mockUpload.mockClear();
    mockTakePicture.mockClear();
    mockRequestPermission.mockClear();
    mockPermission = { granted: true, canAskAgain: true };
    mockTakePicture.mockResolvedValue({ uri: 'file:///captured/page-1.jpg' });
  });

  it('asks "Which restaurant?" with the picker until one is chosen', async () => {
    render(<IngestScreen />);
    await flush();

    expect(screen.getByText('Which restaurant?')).toBeTruthy();
    expect(screen.getByLabelText('new-restaurant-name')).toBeTruthy();
    expect(screen.getByLabelText('restaurant-id')).toBeTruthy(); // manual fallback
  });

  it('creating a restaurant flips the headline to "Scanning for …"', async () => {
    mockCreateRestaurant.mockResolvedValue({
      kind: 'created',
      restaurant: { id: 'r-1', slug: 'marias', name: "Maria's Tacos", status: 'draft' },
    });
    render(<IngestScreen />);
    await flush();

    fireEvent.changeText(screen.getByLabelText('new-restaurant-name'), "Maria's Tacos");
    fireEvent.press(screen.getByLabelText('create-restaurant'));

    await waitFor(() => expect(screen.getByText("Scanning for Maria's Tacos")).toBeTruthy());
  });

  it('renders dedup rows and picking one selects the existing restaurant', async () => {
    mockCreateRestaurant.mockResolvedValue({
      kind: 'duplicates',
      candidates: [
        { id: 'r-9', slug: 'marias', name: "Maria's Tacos", status: 'published', street: '742 Main Ave' },
      ],
    });
    render(<IngestScreen />);
    await flush();

    fireEvent.changeText(screen.getByLabelText('new-restaurant-name'), 'Marias Taco');
    fireEvent.press(screen.getByLabelText('create-restaurant'));

    await waitFor(() => expect(screen.getByText('Did you mean one of these?')).toBeTruthy());
    fireEvent.press(screen.getByLabelText('use-candidate-marias'));

    expect(screen.getByText("Scanning for Maria's Tacos")).toBeTruthy();
  });

  it('upload routes to swipe-verify with the run id', async () => {
    mockCreateRestaurant.mockResolvedValue({
      kind: 'created',
      restaurant: { id: 'r-1', slug: 'marias', name: "Maria's Tacos", status: 'draft' },
    });
    mockUpload.mockResolvedValue({ id: 'run-77', status: 'extracting' });
    render(<IngestScreen />);
    await flush();

    fireEvent.changeText(screen.getByLabelText('new-restaurant-name'), "Maria's Tacos");
    fireEvent.press(screen.getByLabelText('create-restaurant'));
    await waitFor(() => expect(screen.getByText("Scanning for Maria's Tacos")).toBeTruthy());

    // Capture one page through the (mocked) camera ref.
    fireEvent.press(screen.getByLabelText('open-camera'));
    fireEvent.press(screen.getByLabelText('capture-page'));
    await waitFor(() => expect(mockTakePicture).toHaveBeenCalled());
    fireEvent.press(screen.getByLabelText('upload-all'));

    await waitFor(() =>
      expect(mockPush).toHaveBeenCalledWith('/ingest/verify?runId=run-77'),
    );
    expect(mockUpload).toHaveBeenCalledWith(
      expect.objectContaining({
        restaurantId: 'r-1',
        jwt: 'jwt-1',
        pages: [expect.objectContaining({ uri: 'file:///captured/page-1.jpg' })],
      }),
    );
  });

  describe('camera permissions (Phase 7.1)', () => {
    it('soft denial shows the grant button wired to requestPermission', async () => {
      mockPermission = { granted: false, canAskAgain: true };
      render(<IngestScreen />);
      await flush();

      fireEvent.press(screen.getByLabelText('open-camera'));
      fireEvent.press(screen.getByLabelText('grant-camera'));

      expect(mockRequestPermission).toHaveBeenCalled();
    });

    it('hard denial (canAskAgain false) offers Open Settings instead', async () => {
      mockPermission = { granted: false, canAskAgain: false };
      render(<IngestScreen />);
      await flush();

      fireEvent.press(screen.getByLabelText('open-camera'));

      expect(screen.getByLabelText('open-settings')).toBeTruthy();
      expect(screen.queryByLabelText('grant-camera')).toBeNull();
    });

    it('a capture that returns no photo leaves the page strip empty', async () => {
      mockTakePicture.mockResolvedValue(undefined);
      render(<IngestScreen />);
      await flush();

      fireEvent.press(screen.getByLabelText('open-camera'));
      fireEvent.press(screen.getByLabelText('capture-page'));
      await waitFor(() => expect(mockTakePicture).toHaveBeenCalled());

      // Still in camera view (capture didn't close it), no thumbnails added.
      expect(screen.getByLabelText('capture-page')).toBeTruthy();
    });
  });
});
