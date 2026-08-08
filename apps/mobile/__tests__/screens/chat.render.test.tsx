/**
 * The chat screen. Restores the scan path the app lost in M2.
 *
 * What these pin is the safety story rather than the layout: a
 * destructive call never runs without the person answering for it, the
 * answer carries the fingerprint that binds it to the parked call, and
 * what is on screen after a turn is what the server stored.
 *
 * Mocks follow the home.render.test.tsx pattern (mock-prefixed vars +
 * arrow indirection for the hoist).
 */
const mockReplace = jest.fn();
jest.mock('expo-router', () => ({
  router: { push: jest.fn(), replace: (...a: unknown[]) => mockReplace(...a), back: jest.fn() },
  Link: 'Link',
}));

const mockGetJwt = jest.fn();
jest.mock('../../lib/auth', () => ({ getJwt: () => mockGetJwt() }));

jest.mock('expo-image-picker', () => ({
  requestCameraPermissionsAsync: jest.fn(async () => ({ status: 'granted' })),
  requestMediaLibraryPermissionsAsync: jest.fn(async () => ({ status: 'granted' })),
  launchCameraAsync: jest.fn(async () => ({ canceled: true, assets: [] })),
  launchImageLibraryAsync: jest.fn(async () => ({ canceled: true, assets: [] })),
  MediaTypeOptions: { Images: 'Images' },
}));

const mockCreate = jest.fn();
const mockGet = jest.fn();
const mockSend = jest.fn();
const mockEvents = jest.fn();
const mockAnswer = jest.fn();
jest.mock('../../lib/api/chat', () => ({
  ...jest.requireActual('../../lib/api/chat'),
  createConversation: (...a: unknown[]) => mockCreate(...a),
  getConversation: (...a: unknown[]) => mockGet(...a),
  sendMessage: (...a: unknown[]) => mockSend(...a),
  fetchEvents: (...a: unknown[]) => mockEvents(...a),
  answerConfirmation: (...a: unknown[]) => mockAnswer(...a),
}));

import { fireEvent, render, screen, waitFor } from '@testing-library/react-native';
import ChatScreen from '../../app/chat';

const blank = {
  id: 'c-1',
  title: null,
  state: 'active' as const,
  pending: null,
  created_at: '2026-08-08T00:00:00Z',
  updated_at: '2026-08-08T00:00:00Z',
  messages: [],
};

function answered(text: string) {
  return {
    ...blank,
    messages: [
      { id: 'm-1', role: 'user' as const, position: 1, blocks: [{ type: 'text' as const, text: 'hi' }] },
      { id: 'm-2', role: 'assistant' as const, position: 2, blocks: [{ type: 'text' as const, text }] },
    ],
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  mockGetJwt.mockResolvedValue('jwt-token');
  mockCreate.mockResolvedValue(blank);
  mockGet.mockResolvedValue(blank);
  mockSend.mockResolvedValue({ queued: true, after: 0 });
  mockEvents.mockResolvedValue({ events: [], running: false });
  mockAnswer.mockResolvedValue({ queued: true, after: 0 });
});

async function type(text: string) {
  fireEvent.changeText(await screen.findByLabelText('Message'), text);
  fireEvent.press(screen.getByText('Send'));
}

it('opens on a prompt for what to ask', async () => {
  render(<ChatScreen />);

  expect(await screen.findByTestId('chat-welcome')).toBeOnTheScreen();
});

it('sends a signed-out visitor to log in', async () => {
  mockGetJwt.mockResolvedValue(null);

  render(<ChatScreen />);

  await waitFor(() => expect(mockReplace).toHaveBeenCalledWith('/login?next=%2Fchat'));
});

it('creates a conversation on the first message and shows the reply', async () => {
  mockGet.mockResolvedValue(answered('Ninis has 12 dishes you can eat.'));

  render(<ChatScreen />);
  await type('what can I eat');

  await waitFor(() => expect(mockCreate).toHaveBeenCalled());
  expect(await screen.findByText('Ninis has 12 dishes you can eat.')).toBeOnTheScreen();
});

// Mobile polls where web streams — React Native's fetch exposes no
// readable body. `running` is what stops it asking forever.
it('polls the narration until the server says nothing is in flight', async () => {
  mockEvents
    .mockResolvedValueOnce({
      events: [{ type: 'tool_use', name: 'get_menu', doing: "Reading the menu at Nini's", position: 1 }],
      running: true,
    })
    .mockResolvedValueOnce({ events: [{ type: 'done', text: 'Done.', position: 2 }], running: false });
  mockGet.mockResolvedValue(answered('Done.'));

  render(<ChatScreen />);
  await type('what can I eat');

  await waitFor(() => expect(mockEvents).toHaveBeenCalledTimes(2));
  expect(await screen.findByText('Done.')).toBeOnTheScreen();
});

// The human gate. Nothing that publishes or deletes runs because a model
// decided to.
describe('when a destructive call is parked', () => {
  const parked = {
    ...blank,
    state: 'awaiting_confirmation' as const,
    pending: {
      name: 'update_avoid_lists',
      input: { remove_ingredients: ['nut-peanut'] },
      prompt: 'Stop avoiding nut-peanut? Dishes containing it will start showing as safe for you.',
      fingerprint: 'fp-1',
    },
  };

  beforeEach(() => mockGet.mockResolvedValue(parked));

  it('asks with the sentence the tool declared, not the tool name', async () => {
    render(<ChatScreen />);
    await type('stop avoiding peanuts');

    expect(await screen.findByTestId('chat-confirm')).toHaveTextContent(
      /Stop avoiding nut-peanut\?/,
    );
    expect(mockAnswer).not.toHaveBeenCalled();
  });

  // The fingerprint is what stops a screen left open on an earlier prompt
  // approving whatever is parked now.
  it('answers bound to the parked call', async () => {
    render(<ChatScreen />);
    await type('stop avoiding peanuts');

    fireEvent.press(await screen.findByText('No'));

    await waitFor(() => expect(mockAnswer).toHaveBeenCalledWith('jwt-token', 'c-1', false, 'fp-1'));
  });
});

it('shows a failure without losing the conversation', async () => {
  mockSend.mockRejectedValue(new Error('That message is too long.'));

  render(<ChatScreen />);
  await type('x'.repeat(10));

  expect(await screen.findByTestId('chat-error')).toHaveTextContent('That message is too long.');
});
