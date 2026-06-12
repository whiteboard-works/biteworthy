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

  it('typing re-searches (debounced) and a miss suggests scanning', async () => {
    mockSearch.mockResolvedValueOnce([ninis]).mockResolvedValueOnce([]);
    render(<Home />);
    await waitFor(() => expect(screen.getByText('Ninis Taqueria')).toBeTruthy());

    fireEvent.changeText(screen.getByLabelText('restaurant-search'), 'zanzibar');

    await waitFor(() => expect(mockSearch).toHaveBeenLastCalledWith('zanzibar'));
    await waitFor(() =>
      expect(screen.getByText('No matches for “zanzibar”. Scan its menu to add it!')).toBeTruthy(),
    );
  });

  it('tapping a row opens that restaurant menu', async () => {
    mockSearch.mockResolvedValue([ninis]);
    render(<Home />);
    await waitFor(() => expect(screen.getByText('Ninis Taqueria')).toBeTruthy());

    fireEvent.press(screen.getByLabelText('restaurant-ninis-1'));
    expect(mockPush).toHaveBeenCalledWith('/restaurants/rest-1');
  });

  it('scan CTA and profile link route to /ingest and /onboarding', async () => {
    mockSearch.mockResolvedValue([]);
    render(<Home />);
    await waitFor(() => expect(screen.getByLabelText('scan-cta')).toBeTruthy());

    fireEvent.press(screen.getByLabelText('scan-cta'));
    expect(mockPush).toHaveBeenCalledWith('/ingest');

    fireEvent.press(screen.getByLabelText('profile-link'));
    expect(mockPush).toHaveBeenCalledWith('/onboarding');
  });

  it('shows a friendly error when the API is unreachable', async () => {
    mockSearch.mockRejectedValue(new Error('network down'));
    render(<Home />);

    await waitFor(() =>
      expect(screen.getByText(/Couldn’t load restaurants/)).toBeTruthy(),
    );
  });
});
