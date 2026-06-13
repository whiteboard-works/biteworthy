// Mock expo-router so importing the screen module doesn't pull the
// full Stack/Tabs runtime. Params are mutable per test (the helper
// tests don't need any; the Phase 7.3 full-screen tests do).
const mockPush = jest.fn();
let mockParams: Record<string, string> = {};
jest.mock('expo-router', () => ({
  router: {
    push: (...args: unknown[]) => mockPush(...args),
    replace: jest.fn(),
    back: jest.fn(),
  },
  useLocalSearchParams: () => mockParams,
  Link: 'Link',
}));

jest.mock('../../lib/auth', () => ({
  getJwt: jest.fn(() => Promise.resolve(undefined)),
}));

const mockFetchRestaurant = jest.fn();
const mockFetchItems = jest.fn();
jest.mock('../../lib/api/restaurants', () => ({
  ...jest.requireActual('../../lib/api/restaurants'),
  fetchRestaurant: (...args: unknown[]) => mockFetchRestaurant(...args),
  fetchRestaurantItems: (...args: unknown[]) => mockFetchItems(...args),
}));

import { fireEvent, render, screen, waitFor } from '@testing-library/react-native';
import RestaurantScreen, {
  HiddenReasonChip,
  StrictnessToggle,
} from '../../app/restaurants/[id]';
import { TrackerContext } from '../../lib/tracker-context';
import type { Tracker } from '@biteworthy/analytics';

/**
 * Phase post-5 — first JSX render tests for the mobile app.
 *
 * Targets the already-exported helpers (HiddenReasonChip,
 * StrictnessToggle) on the restaurant screen — same as the web
 * counterpart in PR #189. Proves the jest-expo + testing-library/
 * react-native infra works end-to-end on Expo SDK 52.
 *
 * The Phase 4.11.4 ItemRow photo_url contract on mobile isn't
 * covered here — ItemRow is a file-private component inside
 * `app/restaurants/[id].tsx`, and extracting it is a separate
 * scoped follow-up (mirrors the web pattern from PR #190).
 */

describe('HiddenReasonChip (mobile)', () => {
  it('renders the avoid_ingredient label with name + family', () => {
    render(
      <HiddenReasonChip
        reason={{
          kind: 'avoid_ingredient',
          ingredient_id: 'ing-1',
          ingredient_name: 'Cheddar',
          ingredient_family: 'dairy',
        }}
      />,
    );
    expect(screen.getByTestId('chip-avoid_ingredient')).toBeOnTheScreen();
    expect(screen.getByText('Contains dairy (Cheddar)')).toBeOnTheScreen();
  });

  it('renders the avoid_tag label with name + family', () => {
    render(
      <HiddenReasonChip
        reason={{
          kind: 'avoid_tag',
          tag_id: 'tag-1',
          tag_name: 'Contains Dairy',
          tag_family: 'allergen',
        }}
      />,
    );
    expect(screen.getByText('Tagged allergen: Contains Dairy')).toBeOnTheScreen();
  });

  it('renders the unconfirmed_strict label with the confidence value', () => {
    render(
      <HiddenReasonChip
        reason={{ kind: 'unconfirmed_strict', confidence: 'inferred' }}
      />,
    );
    expect(screen.getByText(/inferred/)).toBeOnTheScreen();
  });
});

describe('StrictnessToggle (mobile)', () => {
  it('renders all three strictness modes with the active one selected', () => {
    render(
      <StrictnessToggle active="balanced" loading={false} onChange={() => {}} />,
    );

    const balanced = screen.getByLabelText('strictness-balanced');
    expect(balanced).toBeOnTheScreen();
    expect(balanced.props.accessibilityState).toMatchObject({ selected: true, disabled: false });

    const strict = screen.getByLabelText('strictness-strict');
    expect(strict.props.accessibilityState).toMatchObject({ selected: false, disabled: false });
  });

  it('disables every Pressable + shows the spinner while loading', () => {
    render(
      <StrictnessToggle active="strict" loading={true} onChange={() => {}} />,
    );
    const relaxed = screen.getByLabelText('strictness-relaxed');
    expect(relaxed.props.accessibilityState).toMatchObject({ selected: false, disabled: true });
    expect(screen.getByTestId('strictness-spinner')).toBeOnTheScreen();
  });
});

describe('RestaurantScreen scan-loop wiring (Phase 7.3)', () => {
  const restaurant = {
    id: 'rest-1',
    slug: 'ninis-1',
    name: 'Ninis Taqueria',
    about: null,
    phone: null,
    website: null,
    status: 'published',
    city: { id: 'city-1', slug: 'durango', name: 'Durango', region: 'CO' },
  };
  const itemsResponse = {
    restaurant_id: 'rest-1',
    filter: {
      source: 'none',
      preset_slug: null,
      strictness: 'balanced',
      avoid_ingredient_ids: [],
      avoid_tag_ids: [],
    },
    items: [],
  };

  beforeEach(() => {
    mockPush.mockClear();
    mockFetchRestaurant.mockReset();
    mockFetchItems.mockReset();
    mockFetchRestaurant.mockResolvedValue(restaurant);
    mockFetchItems.mockResolvedValue(itemsResponse);
    mockParams = { id: 'rest-1' };
  });

  it('"Menu changed? Re-scan" routes to /ingest preselecting this restaurant', async () => {
    render(<RestaurantScreen />);
    await waitFor(() => expect(screen.getByText('Ninis Taqueria')).toBeOnTheScreen());

    fireEvent.press(screen.getByLabelText('rescan-menu'));
    expect(mockPush).toHaveBeenCalledWith(
      '/ingest?restaurantId=rest-1&restaurantName=Ninis%20Taqueria',
    );
  });

  it('fires restaurant_tap with the from param carried by the navigation link', async () => {
    mockParams = { id: 'rest-1', from: 'scan' };
    const track = jest.fn();
    const tracker: Tracker = { track, identify: jest.fn(), reset: jest.fn() };
    render(
      <TrackerContext.Provider value={tracker}>
        <RestaurantScreen />
      </TrackerContext.Provider>,
    );
    await waitFor(() => expect(screen.getByText('Ninis Taqueria')).toBeOnTheScreen());

    expect(track).toHaveBeenCalledWith('restaurant_tap', {
      restaurant_slug: 'rest-1',
      from: 'scan',
    });
  });
});
