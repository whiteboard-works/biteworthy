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
import type { Tracker } from '@biteworthy/analytics';
import ChatScreen from '../../app/chat';
import { TrackerContext } from '../../lib/tracker-context';

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
      {
        id: 'm-1',
        role: 'user' as const,
        position: 1,
        blocks: [{ type: 'text' as const, text: 'hi' }],
      },
      {
        id: 'm-2',
        role: 'assistant' as const,
        position: 2,
        blocks: [{ type: 'text' as const, text }],
      },
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

// Mobile never renders the answer as it arrives — `describe` turns
// events into narration lines and drops `text_delta` — so the refetch at
// the end of a turn is the *only* thing that puts the answer on screen.
// A failed one therefore lost the whole turn: the person was left looking
// at their own question with an error under it, for a turn that had in
// fact succeeded and been stored. `done` carries the settled text.
describe('when the post-turn refetch fails', () => {
  it('still shows the answer the turn produced', async () => {
    mockEvents.mockResolvedValue({
      events: [{ type: 'done', text: 'The queso is out — it has dairy.', position: 1 }],
      running: false,
    });
    mockGet.mockRejectedValue(new Error('Network request failed'));

    render(<ChatScreen />);
    await type('what can I eat');

    expect(await screen.findByText('The queso is out — it has dairy.')).toBeOnTheScreen();
  });

  // It is a stand-in, not a second source of truth: the next successful
  // refresh replaces `messages` wholesale, so the local copy cannot
  // linger beside the stored one it was standing in for.
  it('gives way to the stored message on the next refresh', async () => {
    mockEvents.mockResolvedValue({
      events: [{ type: 'done', text: 'Only one of these.', position: 1 }],
      running: false,
    });
    mockGet.mockRejectedValueOnce(new Error('Network request failed'));

    render(<ChatScreen />);
    await type('what can I eat');
    await screen.findByText('Only one of these.');

    mockGet.mockResolvedValue(answered('Only one of these.'));
    await type('and again');

    await waitFor(() => expect(screen.getAllByText('Only one of these.')).toHaveLength(1));
  });
});

// Mobile polls where web streams — React Native's fetch exposes no
// readable body. `running` is what stops it asking forever.
it('polls the narration until the server says nothing is in flight', async () => {
  mockEvents
    .mockResolvedValueOnce({
      events: [
        { type: 'tool_use', name: 'get_menu', doing: "Reading the menu at Nini's", position: 1 },
      ],
      running: true,
    })
    .mockResolvedValueOnce({
      events: [{ type: 'done', text: 'Done.', position: 2 }],
      running: false,
    });
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

  // Dequeuing before delivering is what stops a second flush picking up
  // the same message — but it means a send the server never accepted
  // would vanish with nothing but an error banner to show for it.
  it('puts a queued message back when the send never reaches the server', async () => {
    const release = heldTurn();
    render(<ChatScreen />);
    await type('what can I eat');
    await waitFor(() => expect(mockSend).toHaveBeenCalledTimes(1));
    await type('and check Ninis too');
    await screen.findByTestId('chat-queued');
    mockSend.mockRejectedValueOnce(new Error('Network request failed'));

    release();

    expect(await screen.findByTestId('chat-error')).toHaveTextContent('Network request failed');
    expect(await screen.findByTestId('chat-queued')).toHaveTextContent(/and check Ninis too/);
  });

  // The draft is cleared the instant Send is tapped, so a failed send has
  // to hand it back or the text is gone for good.
  it('gives the draft back when the send fails', async () => {
    mockSend.mockRejectedValueOnce(new Error('Network request failed'));

    render(<ChatScreen />);
    await type('what can I eat');

    await waitFor(() =>
      expect(screen.getByLabelText('Message')).toHaveProp('value', 'what can I eat'),
    );
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

// `chat_turn_completed` feeds the launch funnel, and mobile reported a
// hardcoded `outcome: 'done'` with `tool_count: 0` from a `finally` — so
// every refused, crashed, or still-parked turn arrived as a success, and
// no mobile turn ever showed a tool. The events driving the narration
// carry both facts; they were read for one and dropped for the other.
//
// `useTracker()` falls back to `noopTracker`, which is why nothing caught
// it: the screen has to be wrapped before a call is observable at all.
describe('turn analytics', () => {
  const track = jest.fn();
  const spy = {
    track,
    identify: jest.fn(),
    reset: jest.fn(),
    flush: jest.fn(),
  } as unknown as Tracker;

  const renderTracked = () =>
    render(
      <TrackerContext.Provider value={spy}>
        <ChatScreen />
      </TrackerContext.Provider>,
    );

  const turn = () =>
    track.mock.calls.find(([name]) => name === 'chat_turn_completed')?.[1] as
      { outcome: string; tool_count: number } | undefined;

  beforeEach(() => track.mockClear());

  it('reports what actually happened, not a fixed success', async () => {
    mockEvents
      .mockResolvedValueOnce({
        events: [{ type: 'tool_use', name: 'get_menu', doing: 'Reading', position: 1 }],
        running: true,
      })
      .mockResolvedValueOnce({
        events: [{ type: 'done', text: 'Done.', position: 2 }],
        running: false,
      });
    mockGet.mockResolvedValue(answered('Done.'));

    renderTracked();
    await type('what can I eat');

    await waitFor(() => expect(turn()).toBeDefined());
    expect(turn()).toEqual(expect.objectContaining({ outcome: 'done', tool_count: 1 }));
  });

  it('does not call a refused turn a success', async () => {
    mockSend.mockRejectedValue(new Error('That message is too long.'));

    renderTracked();
    await type('x'.repeat(10));

    await waitFor(() => expect(turn()).toBeDefined());
    expect(turn()).toEqual(expect.objectContaining({ outcome: 'error', tool_count: 0 }));
  });

  // A parked turn is neither a success nor a failure, and the funnel has
  // a third value for exactly that.
  it('reports a turn that stopped for a confirmation', async () => {
    mockEvents.mockResolvedValue({
      events: [{ type: 'awaiting_confirmation', position: 1 }],
      running: false,
    });

    renderTracked();
    await type('delete my review');

    await waitFor(() => expect(turn()).toBeDefined());
    expect(turn()).toEqual(expect.objectContaining({ outcome: 'awaiting_confirmation' }));
  });
});
