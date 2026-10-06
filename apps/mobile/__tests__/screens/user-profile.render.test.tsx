jest.mock('expo-router', () => ({
  router: { push: jest.fn(), replace: jest.fn(), back: jest.fn() },
  useLocalSearchParams: () => ({ handle: 'diner_jane' }),
}));

const mockFetchPublicUserProfile = jest.fn();
jest.mock('../../lib/api/users', () => ({
  fetchPublicUserProfile: (...args: unknown[]) => mockFetchPublicUserProfile(...args),
}));

import { configure, render, screen } from '@testing-library/react-native';
import UserProfileScreen from '../../app/users/[handle]';

configure({ asyncUtilTimeout: 10_000 });

const PROFILE = {
  handle: 'diner_jane',
  display_name: 'Diner Jane',
  bio: null as string | null,
  member_since: '2026-04-01T00:00:00Z',
  reviews_count: 0,
  restaurants_reviewed_count: 0,
  recent_reviews: [],
};

describe('UserProfileScreen — bio', () => {
  it('shows the bio under the name', async () => {
    mockFetchPublicUserProfile.mockResolvedValue({
      ...PROFILE,
      bio: 'Celiac. Will drive for a dedicated fryer.',
    });
    render(<UserProfileScreen />);
    expect(await screen.findByTestId('user-bio')).toHaveTextContent(
      'Celiac. Will drive for a dedicated fryer.',
    );
  });

  it('renders nothing for a profile without one', async () => {
    mockFetchPublicUserProfile.mockResolvedValue({ ...PROFILE });
    render(<UserProfileScreen />);
    await screen.findByText('Diner Jane');
    expect(screen.queryByTestId('user-bio')).toBeNull();
  });
});
