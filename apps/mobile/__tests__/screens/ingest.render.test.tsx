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

jest.mock('expo-camera', () => ({
  CameraView: 'CameraView',
  useCameraPermissions: () => [{ granted: true }, jest.fn()],
}));

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

    // Capture one page through the (mocked) camera.
    fireEvent.press(screen.getByLabelText('open-camera'));
    fireEvent.press(screen.getByLabelText('capture-page'));
    fireEvent.press(screen.getByLabelText('upload-all'));

    await waitFor(() =>
      expect(mockPush).toHaveBeenCalledWith('/ingest/verify?runId=run-77'),
    );
    expect(mockUpload).toHaveBeenCalledWith(
      expect.objectContaining({ restaurantId: 'r-1', jwt: 'jwt-1' }),
    );
  });
});
