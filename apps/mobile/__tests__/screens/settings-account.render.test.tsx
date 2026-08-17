// Mock expo-router so importing the screen doesn't pull the Stack
// runtime. Vars are `mock`-prefixed for Jest's factory hoist, and each
// method is an arrow indirection because the hoist runs the factory
// before the const initialization.
const mockReplace = jest.fn();
const mockPush = jest.fn();
jest.mock('expo-router', () => ({
  router: {
    push: (...args: unknown[]) => mockPush(...args),
    replace: (...args: unknown[]) => mockReplace(...args),
    back: jest.fn(),
  },
  useLocalSearchParams: () => ({}),
  Link: 'Link',
}));

const mockGetJwt = jest.fn();
jest.mock('../../lib/auth', () => ({
  getJwt: (...args: unknown[]) => mockGetJwt(...args),
}));

const mockFetchMe = jest.fn();
const mockUpdateMyHandle = jest.fn();
jest.mock('../../lib/api/me', () => {
  // Plain field assignment, not a TS parameter property — the hoist
  // checker rejects the desugared reference unless it is mock-prefixed.
  class MeValidationError extends Error {
    readonly messages: string[];
    constructor(mockMessages: string[]) {
      super(mockMessages.join(', '));
      this.name = 'MeValidationError';
      this.messages = mockMessages;
    }
  }
  class MeError extends Error {
    readonly status: number;
    constructor(mockStatus: number, message: string) {
      super(message);
      this.name = 'MeError';
      this.status = mockStatus;
    }
  }
  return {
    fetchMe: (...args: unknown[]) => mockFetchMe(...args),
    updateMyHandle: (...args: unknown[]) => mockUpdateMyHandle(...args),
    MeError,
    MeValidationError,
  };
});
import { MeError, MeValidationError } from '../../lib/api/me';

import { act, configure, fireEvent, render, screen } from '@testing-library/react-native';
import AccountSettingsScreen from '../../app/settings/account';

configure({ asyncUtilTimeout: 10_000 });

/**
 * Settings → Account renders the signed-in user's handle and edits it
 * through PATCH /me. The pins: signed-out visitors bounce to /login
 * with a way back, Save is inert until the handle actually changes,
 * and a taken-handle 422 reads as an inline field answer, not a crash.
 */

const ME = {
  id: 'u-1',
  email: 'sky@example.com',
  handle: 'diner_ab12cd34',
  display_name: 'Sky',
  is_admin: false,
  is_super_admin: false,
};

beforeEach(() => {
  mockReplace.mockReset();
  mockPush.mockReset();
  mockGetJwt.mockReset().mockResolvedValue('jwt-123');
  mockFetchMe.mockReset().mockResolvedValue({ ...ME });
  mockUpdateMyHandle.mockReset().mockResolvedValue({ ...ME, handle: 'chosen_name' });
});

describe('AccountSettingsScreen', () => {
  it('bounces a signed-out visitor to login with a way back', async () => {
    mockGetJwt.mockResolvedValue(null);
    render(<AccountSettingsScreen />);

    await act(async () => {});
    expect(mockReplace).toHaveBeenCalledWith('/login?next=%2Fsettings%2Faccount');
    expect(mockFetchMe).not.toHaveBeenCalled();
  });

  it('treats a stored-but-stale token as signed out, not a dead-end error', async () => {
    mockFetchMe.mockRejectedValue(new MeError(401, 'fetchMe failed: 401'));
    render(<AccountSettingsScreen />);

    await act(async () => {});
    expect(mockReplace).toHaveBeenCalledWith('/login?next=%2Fsettings%2Faccount');
    expect(screen.queryByTestId('account-load-error')).toBeNull();
  });

  it('loads and shows the current handle', async () => {
    render(<AccountSettingsScreen />);

    const input = await screen.findByLabelText('username');
    expect(input.props.value).toBe('diner_ab12cd34');
    expect(mockFetchMe).toHaveBeenCalledWith('jwt-123');
  });

  it('saves the trimmed handle and confirms the new identity', async () => {
    render(<AccountSettingsScreen />);
    const input = await screen.findByLabelText('username');

    fireEvent.changeText(input, '  Chosen_Name ');
    await act(async () => {
      fireEvent.press(screen.getByLabelText('username-save'));
    });

    expect(mockUpdateMyHandle).toHaveBeenCalledWith('Chosen_Name', 'jwt-123');
    expect(screen.getByTestId('username-saved')).toHaveTextContent(/@chosen_name/);
  });

  it('does nothing when the handle is unchanged (case-insensitively)', async () => {
    render(<AccountSettingsScreen />);
    const input = await screen.findByLabelText('username');

    fireEvent.changeText(input, 'Diner_AB12cd34');
    await act(async () => {
      fireEvent.press(screen.getByLabelText('username-save'));
    });

    expect(mockUpdateMyHandle).not.toHaveBeenCalled();
  });

  it('renders a taken handle as an inline field error', async () => {
    mockUpdateMyHandle.mockRejectedValue(new MeValidationError(['has already been taken']));
    render(<AccountSettingsScreen />);
    const input = await screen.findByLabelText('username');

    fireEvent.changeText(input, 'somebody_else');
    await act(async () => {
      fireEvent.press(screen.getByLabelText('username-save'));
    });

    expect(screen.getByTestId('username-error')).toHaveTextContent(
      'Username has already been taken.',
    );
  });

  it('links to the public profile at the current handle', async () => {
    render(<AccountSettingsScreen />);
    await screen.findByLabelText('username');

    fireEvent.press(screen.getByLabelText('view-public-profile'));
    expect(mockPush).toHaveBeenCalledWith('/users/diner_ab12cd34');
  });
});
