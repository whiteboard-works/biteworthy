/**
 * Phase 7.2 — the real home screen: search published restaurants,
 * tap a row to open its menu, or jump into the scan flow. Mocks
 * follow the ingest.render.test.tsx pattern (mock-prefixed vars +
 * arrow indirection for the hoist).
 */
const mockPush = jest.fn();
jest.mock('expo-router', () => ({
  router: {
    push: (...args: unknown[]) => mockPush(...args),
    replace: jest.fn(),
    back: jest.fn(),
  },
  Link: 'Link',
}));

const mockSearch = jest.fn();
jest.mock('../../lib/api/restaurants', () => ({
  ...jest.requireActual('../../lib/api/restaurants'),
  searchRestaurants: (...args: unknown[]) => mockSearch(...args),
}));

import { fireEvent, render, screen, waitFor } from '@testing-library/react-native';
import Home from '../../app/index';

const ninis = {
  id: 'rest-1',
  slug: 'ninis-1',
  name: 'Ninis Taqueria',
  status: 'published',
  city: { slug: 'durango', name: 'Durango', region: 'CO' },
  street: '119 W College Dr',
  latitude: 37.27,
  longitude: -107.88,
};

describe('Home (Phase 7.2)', () => {
  beforeEach(() => {
    mockPush.mockClear();
    mockSearch.mockReset();
  });

  it('loads and lists restaurants on mount (no query)', async () => {
    mockSearch.mockResolvedValue([ninis]);
    render(<Home />);

    await waitFor(() => expect(screen.getByText('Ninis Taqueria')).toBeTruthy());
    expect(mockSearch).toHaveBeenCalledWith('');
    expect(screen.getByText('119 W College Dr · Durango, CO')).toBeTruthy();
  });

  it('typing re-searches (debounced) and reports a miss', async () => {
    mockSearch.mockResolvedValueOnce([ninis]).mockResolvedValueOnce([]);
    render(<Home />);
    await waitFor(() => expect(screen.getByText('Ninis Taqueria')).toBeTruthy());

    fireEvent.changeText(screen.getByLabelText('restaurant-search'), 'zanzibar');

    await waitFor(() => expect(mockSearch).toHaveBeenLastCalledWith('zanzibar'));
    await waitFor(() => expect(screen.getByText(/No matches for/)).toBeTruthy());
  });

  it('tapping a row opens that restaurant menu with from=search', async () => {
    mockSearch.mockResolvedValue([ninis]);
    render(<Home />);
    await waitFor(() => expect(screen.getByText('Ninis Taqueria')).toBeTruthy());

    fireEvent.press(screen.getByLabelText('restaurant-ninis-1'));
    expect(mockPush).toHaveBeenCalledWith('/restaurants/rest-1?from=search');
  });

  it('profile link routes to onboarding', async () => {
    mockSearch.mockResolvedValue([]);
    render(<Home />);
    await waitFor(() => expect(screen.getByLabelText('profile-link')).toBeTruthy());

    fireEvent.press(screen.getByLabelText('profile-link'));
    expect(mockPush).toHaveBeenCalledWith('/onboarding');
  });

  // Scanning moved to the tool layer; the screen must not advertise a
  // destination that no longer exists.
  it('no longer offers a scan entry point', async () => {
    mockSearch.mockResolvedValue([]);
    render(<Home />);
    await waitFor(() => expect(screen.getByLabelText('profile-link')).toBeTruthy());

    expect(screen.queryByLabelText('scan-cta')).toBeNull();
    expect(screen.queryByLabelText('scan-miss-cta')).toBeNull();
  });

  it('shows a friendly error when the API is unreachable', async () => {
    mockSearch.mockRejectedValue(new Error('network down'));
    render(<Home />);

    await waitFor(() =>
      expect(screen.getByText(/Couldn’t load restaurants/)).toBeTruthy(),
    );
  });
});

// The scan path the app lost in M2. An entry point nobody can reach is
// not a restored feature.
it('offers the chat from the home screen', async () => {
  mockSearch.mockResolvedValue({ restaurants: [ninis], total: 1 });

  render(<Home />);

  fireEvent.press(await screen.findByLabelText('chat-link'));

  expect(mockPush).toHaveBeenCalledWith('/chat');
});


// The calver from @biteworthy/version-history is the app's only
// user-visible version (app.json's store version is decoupled).
it('shows the current version on the home screen', async () => {
  mockSearch.mockResolvedValue({ restaurants: [ninis], total: 1 });

  render(<Home />);

  const version = await screen.findByLabelText('app-version');
  expect(version).toHaveTextContent(/^BiteWorthy v\d{4}\.\d{1,2}\.\d{1,2}(\.\d+)?$/);
});
