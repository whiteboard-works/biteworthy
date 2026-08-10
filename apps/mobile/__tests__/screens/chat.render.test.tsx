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
const mockSetMode = jest.fn();
jest.mock('../../lib/api/chat', () => ({
  ...jest.requireActual('../../lib/api/chat'),
  createConversation: (...a: unknown[]) => mockCreate(...a),
  getConversation: (...a: unknown[]) => mockGet(...a),
  sendMessage: (...a: unknown[]) => mockSend(...a),
  fetchEvents: (...a: unknown[]) => mockEvents(...a),
  answerConfirmation: (...a: unknown[]) => mockAnswer(...a),
  setConversationMode: (...a: unknown[]) => mockSetMode(...a),
}));

import { fireEvent, render, screen, waitFor } from '@testing-library/react-native';
import ChatScreen from '../../app/chat';

const blank = {
  id: 'c-1',
  title: null,
  state: 'active' as const,
  mode: 'manual' as const,
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
  mockSetMode.mockResolvedValue(blank);
});

async function type(text: string) {
  fireEvent.changeText(await screen.findByLabelText('Message'), text);
  // "Send" when idle, "Queue" while a turn is running — the button says
  // which of the two pressing it will do.
  fireEvent.press(screen.getByText(/^(Send|Queue)$/));
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

    await waitFor(() =>
      expect(mockAnswer).toHaveBeenCalledWith('jwt-token', 'c-1', false, 'fp-1', 'manual'),
    );
  });

  // The composer used to go dead here, which meant a parked confirmation
  // also blocked "actually, never mind, do X instead" — the message most
  // likely to be typed at exactly that moment.
  it('still takes a message while the confirmation waits, and holds it', async () => {
    render(<ChatScreen />);
    await type('stop avoiding peanuts');
    await screen.findByTestId('chat-confirm');

    await type('actually, leave it');

    expect(await screen.findByTestId('chat-queued')).toHaveTextContent(/actually, leave it/);
    expect(mockSend).toHaveBeenCalledTimes(1);
  });
});

// A menu scan is a minute or more. The input used to go dead for all of
// it, so a thought that arrived during one had nowhere to go.
describe('typing while a turn is running', () => {
  // Two poll rounds with `running: true` first, so the turn is still in
  // flight while the second message is typed.
  function heldTurn() {
    let release = () => {};
    mockEvents.mockImplementation(
      () =>
        new Promise((resolve) => {
          release = () => resolve({ events: [], running: false });
        }),
    );
    return () => release();
  }

  it('queues the message rather than dropping it or sending it now', async () => {
    const release = heldTurn();
    render(<ChatScreen />);
    await type('what can I eat');
    await waitFor(() => expect(mockSend).toHaveBeenCalledTimes(1));

    await type('and check Ninis too');

    expect(await screen.findByTestId('chat-queued')).toHaveTextContent(/and check Ninis too/);
    expect(mockSend).toHaveBeenCalledTimes(1);
    release();
  });

  it('sends it once the turn it was typed during finishes', async () => {
    const release = heldTurn();
    render(<ChatScreen />);
    await type('what can I eat');
    await waitFor(() => expect(mockSend).toHaveBeenCalledTimes(1));
    await type('and check Ninis too');
    await screen.findByTestId('chat-queued');

    release();

    await waitFor(() =>
      expect(mockSend).toHaveBeenCalledWith('jwt-token', 'c-1', 'and check Ninis too', 'manual'),
    );
  });
});

// The gate is the server's. The picker only says which one to use.
describe('the mode picker', () => {
  it('opens in the mode the server stored', async () => {
    mockGet.mockResolvedValue({ ...answered('ok'), mode: 'accept_edits' as const });

    render(<ChatScreen />);
    await type('hi');

    await waitFor(() =>
      expect(screen.getByLabelText('Edits mode').props.accessibilityState).toMatchObject({
        selected: true,
      }),
    );
  });

  it('persists a switch so it survives a reload', async () => {
    render(<ChatScreen />);
    await type('hi');
    await waitFor(() => expect(mockSend).toHaveBeenCalled());

    fireEvent.press(screen.getByLabelText('Plan mode'));

    await waitFor(() => expect(mockSetMode).toHaveBeenCalledWith('jwt-token', 'c-1', 'planning'));
  });

  // Someone in `auto` has switched off the only place a destructive call
  // stops for a human. That has to be readable without opening anything.
  it('says so on screen when the mode is not the default', async () => {
    render(<ChatScreen />);
    await screen.findByTestId('chat-welcome');
    expect(screen.queryByTestId('chat-mode-notice')).toBeNull();

    fireEvent.press(screen.getByLabelText('Auto mode'));

    expect(await screen.findByTestId('chat-mode-notice')).toHaveTextContent('Never asks.');
  });
});

it('shows a failure without losing the conversation', async () => {
  mockSend.mockRejectedValue(new Error('That message is too long.'));

  render(<ChatScreen />);
  await type('x'.repeat(10));

  expect(await screen.findByTestId('chat-error')).toHaveTextContent('That message is too long.');
});
