import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import type { ChatEvent, Conversation } from '../../../lib/chat';

/**
 * The chat surface. Two properties matter more than the layout: a
 * destructive tool never runs without the person answering for it, and
 * what's on screen after a turn is what the server actually stored — the
 * stream is a view, not the record.
 */

const mockReplace = vi.fn();
vi.mock('next/navigation', () => ({ useRouter: () => ({ replace: mockReplace }) }));

const listConversations = vi.fn();
const createConversation = vi.fn();
const getConversation = vi.fn();
const deleteConversation = vi.fn();
const sendMessage = vi.fn();
const answerConfirmation = vi.fn();
const watchTurn = vi.fn();
const stopTurn = vi.fn();
const uploadAttachment = vi.fn();
const setConversationMode = vi.fn();

vi.mock('../../../lib/chat', async () => {
  const actual = await vi.importActual<typeof import('../../../lib/chat')>('../../../lib/chat');
  return {
    ...actual,
    listConversations: () => listConversations(),
    createConversation: () => createConversation(),
    getConversation: (id: string) => getConversation(id),
    deleteConversation: (id: string) => deleteConversation(id),
    sendMessage: (id: string, text: string, context?: unknown, mode?: unknown) =>
      sendMessage(id, text, context, mode),
    answerConfirmation: (id: string, ok: boolean, fingerprint: string | null, mode?: unknown) =>
      answerConfirmation(id, ok, fingerprint, mode),
    setConversationMode: (id: string, mode: unknown) => setConversationMode(id, mode),
    watchTurn: (id: string, after: number, onEvent: (e: ChatEvent) => void) =>
      watchTurn(id, after, onEvent),
    stopTurn: (id: string) => stopTurn(id),
    uploadAttachment: (file: File) => uploadAttachment(file),
  };
});

const { ChatClient } = await import('../_ChatClient');

const blank: Conversation = {
  id: 'c-1',
  title: null,
  state: 'active',
  mode: 'manual',
  pending: null,
  created_at: '2026-08-08T00:00:00Z',
  updated_at: '2026-08-08T00:00:00Z',
  messages: [],
};

function answered(text: string): Conversation {
  return {
    ...blank,
    title: 'hi',
    messages: [
      { id: 'm-1', role: 'user', position: 1, blocks: [{ type: 'text', text: 'hi' }] },
      { id: 'm-2', role: 'assistant', position: 2, blocks: [{ type: 'text', text }] },
    ],
  };
}

beforeEach(() => {
  listConversations.mockResolvedValue({ conversations: [] });
  createConversation.mockResolvedValue(blank);
  getConversation.mockResolvedValue(blank);
  // Asking for a turn now returns immediately; the narration is watched
  // separately, so tests drive the two halves independently.
  sendMessage.mockResolvedValue({ queued: true, after: 0 });
  answerConfirmation.mockResolvedValue({ queued: true, after: 0 });
  watchTurn.mockResolvedValue(null);
  stopTurn.mockResolvedValue(undefined);
  setConversationMode.mockResolvedValue(blank);
});

afterEach(() => {
  vi.clearAllMocks();
});

async function type(text: string) {
  fireEvent.change(await screen.findByLabelText('Message'), { target: { value: text } });
  // "Send" when idle, "Queue" while a turn is running — the button says
  // which of the two pressing it will do.
  fireEvent.click(screen.getByRole('button', { name: /^(Send|Queue)$/ }));
}

describe('ChatClient', () => {
  it('opens on a prompt for what to ask', async () => {
    render(<ChatClient />);

    expect(await screen.findByTestId('chat-welcome')).toBeInTheDocument();
  });

  it('creates a conversation on the first message and streams the reply', async () => {
    watchTurn.mockImplementation(async (_id, _after, onEvent) => {
      onEvent({ type: 'text_delta', text: 'Ninis has 12 dishes you can eat.' });
      onEvent({ type: 'done', text: 'Ninis has 12 dishes you can eat.' });
    });
    getConversation.mockResolvedValue(answered('Ninis has 12 dishes you can eat.'));

    render(<ChatClient />);
    await type('hi');

    expect(createConversation).toHaveBeenCalled();
    // Asserted on the settled assistant bubble rather than by matching a
    // bare text node. The streaming turn and the persisted message render
    // the same words in different subtrees, so a `findByText` can resolve
    // to the live node an instant before `done` unmounts it — leaving a
    // detached element and a confusing "not in the document". What the
    // reader cares about is that the answer landed in the assistant's
    // message, which is what this now says.
    expect(await screen.findByTestId('assistant-message')).toHaveTextContent(
      'Ninis has 12 dishes you can eat.',
    );
  });

  // Dropping data the model was working from shows up later as the
  // assistant mysteriously forgetting a menu it had already read. A
  // person who was not told has no way to connect the two.
  it('says when it trimmed stale tool results to stay in budget', async () => {
    const inFlight: { release: () => void } = { release: () => {} };
    watchTurn.mockImplementation((_id: string, _after: number, onEvent: (e: ChatEvent) => void) => {
      onEvent({ type: 'compacted', messages: 4, tokens_saved: 61000 });
      return new Promise<void>((resolve) => (inFlight.release = resolve));
    });

    render(<ChatClient />);
    await type('what can I eat');

    expect(await screen.findByTestId('live-notice')).toHaveTextContent(
      /Trimmed 4 earlier tool results/,
    );
    inFlight.release();
  });

  // The tool's own sentence, not its function name — it is the only thing
  // a person can read while a turn is working, so the assertion has to
  // happen while the turn is still in flight.
  it('narrates a running tool with the sentence the tool declared', async () => {
    const inFlight: { release: () => void } = { release: () => {} };
    watchTurn.mockImplementation((_id: string, _after: number, onEvent: (e: ChatEvent) => void) => {
      onEvent({
        type: 'tool_use',
        name: 'get_menu',
        input: {},
        doing: "Reading the menu at Nini's",
      });
      return new Promise<void>((resolve) => (inFlight.release = resolve));
    });

    render(<ChatClient />);
    await type('what can I eat');

    expect(await screen.findByTestId('tool-card')).toHaveTextContent("Reading the menu at Nini's");
    inFlight.release();
  });

  it('falls back to the humanized name when a tool declares nothing', async () => {
    watchTurn.mockImplementation(async (_id, _after, onEvent) => {
      onEvent({ type: 'tool_use', name: 'get_menu', input: {} });
      onEvent({ type: 'tool_result', name: 'get_menu', ok: true });
      onEvent({ type: 'done', text: 'Here you go.' });
    });
    getConversation.mockResolvedValue({
      ...blank,
      messages: [
        {
          id: 'm-1',
          role: 'assistant',
          position: 1,
          blocks: [
            { type: 'tool_use', id: 't-1', name: 'get_menu', input: { restaurant: 'ninis' } },
          ],
        },
        {
          id: 'm-2',
          role: 'user',
          position: 2,
          blocks: [{ type: 'tool_result', tool_use_id: 't-1', ok: true, text: '12 dishes' }],
        },
      ],
    });

    render(<ChatClient />);
    await type('what can I eat');

    expect(await screen.findByTestId('tool-card')).toHaveTextContent('get menu');
  });

  // The human gate. Nothing that publishes or deletes runs because a
  // model decided to.
  describe('when a destructive call is parked', () => {
    beforeEach(() => {
      watchTurn.mockImplementation(async (_id, _after, onEvent) => {
        onEvent({
          type: 'awaiting_confirmation',
          tool: { name: 'delete_review', input: { id: 'r-1' }, prompt: null, fingerprint: 'fp-1' },
        });
      });
      getConversation.mockResolvedValue({
        ...blank,
        state: 'awaiting_confirmation',
        pending: { name: 'delete_review', input: { id: 'r-1' }, prompt: null, fingerprint: 'fp-1' },
      });
    });

    // The composer stays live. It used to go dead here, which meant a
    // parked confirmation also blocked "actually, never mind, do X
    // instead" — the message most likely to be typed at exactly that
    // moment. It queues behind the answer instead.
    it('asks before running it, and keeps the composer usable meanwhile', async () => {
      render(<ChatClient />);
      await type('delete my review');

      expect(await screen.findByTestId('confirm-prompt')).toHaveTextContent('delete review');
      expect(answerConfirmation).not.toHaveBeenCalled();
      expect(screen.getByLabelText('Message')).toBeEnabled();
    });

    // The fingerprint has to travel with the answer, or the server cannot
    // tell this approval apart from one meant for a different call.
    it('sends the answer the person gave, bound to the parked call', async () => {
      render(<ChatClient />);
      await type('delete my review');

      fireEvent.click(await screen.findByText('No'));

      await waitFor(() =>
        expect(answerConfirmation).toHaveBeenCalledWith('c-1', false, 'fp-1', 'manual'),
      );
    });

    // A declared sentence replaces the generic prompt and the JSON dump:
    // people should not have to read arguments to know what they are
    // agreeing to.
    it('renders the sentence the tool declared when there is one', async () => {
      const prompt =
        'Stop avoiding nut-peanut? Dishes containing it will start showing as safe for you.';
      getConversation.mockResolvedValue({
        ...blank,
        state: 'awaiting_confirmation',
        pending: {
          name: 'update_avoid_lists',
          input: { remove_ingredients: ['nut-peanut'] },
          prompt,
          fingerprint: 'fp-2',
        },
      });
      render(<ChatClient />);
      await type('stop avoiding peanuts');

      expect(await screen.findByTestId('confirm-prompt')).toHaveTextContent(prompt);
    });
  });

  // The turn runs in a job, so stopping it is a separate request — the one
  // that started it is long gone.
  it('offers a stop while a turn is in flight, and raises the flag', async () => {
    // Held open so the turn is still "in flight" when Stop is clicked.
    const inFlight: { release: () => void } = { release: () => {} };
    watchTurn.mockImplementation(
      () => new Promise<void>((resolve) => (inFlight.release = resolve)),
    );

    render(<ChatClient />);
    await type('what can I eat');

    fireEvent.click(await screen.findByText('Stop'));

    await waitFor(() => expect(stopTurn).toHaveBeenCalledWith('c-1'));
    inFlight.release();
  });

  // Spend accounting is admin-only, and the server decides — the client
  // renders what it was sent and nothing more, so there is no visibility
  // check here to get wrong.
  describe('usage pills', () => {
    // Two scopes, and they must not read as one number. The old footer
    // showed only the conversation lifetime, labelled "total", next to
    // per-run token counts — so "203¢ total · 1,200 in" invited the
    // arithmetic that says 1,200 tokens cost two dollars.
    it("shows the turn's cost and the conversation's separately", async () => {
      getConversation.mockResolvedValue({
        ...answered('ok'),
        usage: {
          cost_cents: 34,
          last_run: {
            outcome: 'done',
            state: 'done',
            rounds: 3,
            input_tokens: 1200,
            output_tokens: 400,
            cache_read_tokens: 7550,
            cache_write_tokens: 2100,
            cost_cents: 9,
            duration_ms: 8200,
          },
        },
      });

      render(<ChatClient />);
      await type('hi');

      const pills = await screen.findByTestId('usage-pills');
      expect(pills).toHaveTextContent('9¢ turn');
      expect(pills).toHaveTextContent('34¢ conversation');
      // Cache writes bill at 1.25× input and were recorded but never shown.
      expect(pills).toHaveTextContent('7,550 cache r / 2,100 w');
      expect(pills).toHaveTextContent('8.2s');
    });

    // The reported symptom: "203¢ total · 0 rounds · 0 cached ·
    // 0 in / 0 out · 0.1s · error". A turn refused before its first round
    // still leaves an all-zero run behind, so the numbers and the
    // refusal belong to different runs. Show the last real numbers and
    // the latest outcome, rather than one run's zeroes labelled as both.
    it('keeps the last working turn on screen when a later one was refused', async () => {
      getConversation.mockResolvedValue({
        ...answered('ok'),
        usage: {
          cost_cents: 203,
          last_outcome: { outcome: 'error', state: 'failed' },
          last_run: {
            outcome: 'done',
            state: 'done',
            rounds: 4,
            input_tokens: 1200,
            output_tokens: 400,
            cache_read_tokens: 7550,
            cache_write_tokens: 0,
            cost_cents: 21,
            duration_ms: 8200,
          },
        },
      });

      render(<ChatClient />);
      await type('hi');

      const pills = await screen.findByTestId('usage-pills');
      expect(pills).toHaveTextContent('4 rounds');
      expect(pills).toHaveTextContent('1,200 in / 400 out');
      expect(pills).toHaveTextContent('error');
      expect(pills).not.toHaveTextContent('0 rounds');
    });

    // Showing only the newest outcome would hide the failure behind a
    // harmless one: two messages sent quickly, one job drains both, the
    // second turn times out with 8 rounds, then a second job finds
    // nothing queued and releases `nothing_queued`. The numbers on
    // screen would be the timed-out run's under a benign label.
    it('shows the failure of the run the numbers came from, not a benign newer one', async () => {
      getConversation.mockResolvedValue({
        ...answered('ok'),
        usage: {
          cost_cents: 88,
          last_outcome: { outcome: 'nothing_queued', state: 'done' },
          last_run: {
            outcome: 'timed_out',
            state: 'failed',
            rounds: 8,
            input_tokens: 9000,
            output_tokens: 500,
            cache_read_tokens: 0,
            cache_write_tokens: 0,
            cost_cents: 44,
            duration_ms: 600000,
          },
        },
      });

      render(<ChatClient />);
      await type('hi');

      const pills = await screen.findByTestId('usage-pills');
      expect(pills).toHaveTextContent('timed_out');
      expect(pills).not.toHaveTextContent('nothing_queued');
    });

    it('renders nothing when the server withheld it', async () => {
      getConversation.mockResolvedValue(answered('ok'));

      render(<ChatClient />);
      await type('hi');

      await screen.findByText('ok');
      expect(screen.queryByTestId('usage-pills')).not.toBeInTheDocument();
    });
  });

  // A menu scan legitimately outlives one connection. The reconnect has to
  // be invisible: the narration continues on screen and the turn is not
  // treated as finished.
  // Showing every tool call is the honest-disclosure claim made visible,
  // so hiding is a per-person preference and never the default. These pin
  // both halves: it is on unless someone turned it off, and turning it
  // off does not touch the answer itself.
  describe('the tool-visibility toggle', () => {
    const withTool: Conversation = {
      ...blank,
      title: 'hi',
      messages: [
        {
          id: 'm-1',
          role: 'assistant',
          position: 1,
          created_at: '2026-08-10T01:30:00Z',
          blocks: [
            { type: 'tool_use', id: 't1', name: 'get_menu', input: {} },
            { type: 'text', text: 'Ninis has 12 dishes you can eat.' },
          ],
        },
      ],
    };

    beforeEach(() => {
      window.localStorage.clear();
      getConversation.mockResolvedValue(withTool);
    });

    it('shows tool cards by default', async () => {
      render(<ChatClient />);
      await type('hi');

      expect(await screen.findByTestId('tool-card')).toBeInTheDocument();
    });

    // A stable name plus a pressed state, not an action label. "Hide
    // tools" with `aria-pressed={showTools}` announces as "Hide tools,
    // pressed" in exactly the state where tools are still showing, which
    // is the opposite of the truth.
    it('announces its state rather than its action', async () => {
      render(<ChatClient />);
      await type('hi');
      await screen.findByTestId('tool-card');

      const toggle = screen.getByTestId('tools-toggle');
      expect(toggle).toHaveTextContent('Tools');
      expect(toggle).toHaveAttribute('aria-pressed', 'true');

      fireEvent.click(toggle);

      expect(toggle).toHaveAttribute('aria-pressed', 'false');
    });

    it('hides them on request and keeps the answer', async () => {
      render(<ChatClient />);
      await type('hi');
      await screen.findByTestId('tool-card');

      fireEvent.click(screen.getByTestId('tools-toggle'));

      expect(screen.queryByTestId('tool-card')).toBeNull();
      expect(screen.getByTestId('assistant-message')).toHaveTextContent(
        'Ninis has 12 dishes you can eat.',
      );
    });

    it('remembers the choice', async () => {
      render(<ChatClient />);
      await type('hi');
      await screen.findByTestId('tool-card');

      fireEvent.click(screen.getByTestId('tools-toggle'));

      expect(window.localStorage.getItem('bw_chat_show_tools')).toBe('false');
    });

    // Next to the machinery, not on every bubble: a timestamp on each
    // line is noise in a conversation you are having, and "when did it do
    // that" is the tool view's question.
    it('timestamps the tool card', async () => {
      render(<ChatClient />);
      await type('hi');

      const card = await screen.findByTestId('tool-card');
      expect(within(card).getByRole('time')).toHaveAttribute('datetime', '2026-08-10T01:30:00Z');
    });
  });

  it('resumes from the cursor when a turn outlives one connection', async () => {
    watchTurn
      .mockImplementationOnce(
        async (_id: string, _after: number, onEvent: (e: ChatEvent) => void) => {
          onEvent({ type: 'text_delta', text: 'Reading ' });
          return 7; // server closed mid-turn, resume from position 7
        },
      )
      .mockImplementationOnce(
        async (_id: string, after: number, onEvent: (e: ChatEvent) => void) => {
          expect(after).toBe(7);
          onEvent({ type: 'done', text: 'Reading the menu.' });
          return null;
        },
      );
    getConversation.mockResolvedValue(answered('Reading the menu.'));

    render(<ChatClient />);
    await type('scan this');

    await waitFor(() => expect(watchTurn).toHaveBeenCalledTimes(2));
    // Settled bubble, not a bare text node — the live turn and the
    // persisted message render the same words in different subtrees, so
    // matching the text can resolve to the node `done` is about to
    // unmount. Same reason as the streaming test above.
    expect(await screen.findByTestId('assistant-message')).toHaveTextContent('Reading the menu.');
  });

  it('shows an error event without losing the conversation', async () => {
    watchTurn.mockImplementation(async (_id, _after, onEvent) => {
      onEvent({ type: 'error', message: 'This conversation has reached its spend limit.' });
    });

    render(<ChatClient />);
    await type('hi');

    expect(await screen.findByTestId('chat-error')).toHaveTextContent('spend limit');
  });

  // A turn is a minute or more of a menu scan. The input used to go dead
  // for all of it, so the next thought had nowhere to go but the user's
  // memory.
  describe('typing while a turn is running', () => {
    // Held open so the first turn is still in flight while the second
    // message is typed.
    // Resolves with `null` — "the turn is genuinely over" — rather than
    // undefined, which the client reads as a dropped connection and
    // reconnects from.
    function heldTurn() {
      const inFlight: { release: () => void } = { release: () => {} };
      watchTurn.mockImplementation(
        () => new Promise<number | null>((resolve) => (inFlight.release = () => resolve(null))),
      );
      return inFlight;
    }

    it('queues the message rather than dropping it or sending it now', async () => {
      const inFlight = heldTurn();
      render(<ChatClient />);
      await type('what can I eat');
      await waitFor(() => expect(sendMessage).toHaveBeenCalledTimes(1));

      await type('and check Ninis too');

      expect(await screen.findByTestId('queued-messages')).toHaveTextContent('and check Ninis too');
      expect(sendMessage).toHaveBeenCalledTimes(1);
      inFlight.release();
    });

    it('sends it once the turn it was typed during finishes', async () => {
      const inFlight = heldTurn();
      render(<ChatClient />);
      await type('what can I eat');
      await waitFor(() => expect(sendMessage).toHaveBeenCalledTimes(1));
      await type('and check Ninis too');
      await screen.findByTestId('queued-messages');

      inFlight.release();

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-1', 'and check Ninis too', undefined, 'manual'),
      );
      expect(screen.queryByTestId('queued-messages')).toBeNull();
    });

    // "Queued" and "sent" are different promises. The commonest reason to
    // want it back is the assistant answering it unprompted while the
    // user was still typing.
    it('lets a queued message be taken back before it leaves', async () => {
      const inFlight = heldTurn();
      render(<ChatClient />);
      await type('what can I eat');
      await waitFor(() => expect(sendMessage).toHaveBeenCalledTimes(1));
      await type('never mind');
      await screen.findByTestId('queued-messages');

      fireEvent.click(screen.getByLabelText('Cancel queued message: never mind'));
      inFlight.release();

      await waitFor(() => expect(screen.queryByTestId('queued-messages')).toBeNull());
      expect(sendMessage).toHaveBeenCalledTimes(1);
    });

    // Dequeuing before delivering is what stops a second flush picking up
    // the same message — but it means a send the server never accepted
    // would vanish with nothing but an error banner to show for it.
    it('puts a queued message back when the send never reaches the server', async () => {
      const inFlight = heldTurn();
      render(<ChatClient />);
      await type('what can I eat');
      await waitFor(() => expect(sendMessage).toHaveBeenCalledTimes(1));
      await type('and check Ninis too');
      await screen.findByTestId('queued-messages');
      sendMessage.mockRejectedValueOnce(new Error('Network request failed'));

      inFlight.release();

      expect(await screen.findByTestId('chat-error')).toHaveTextContent('Network request failed');
      expect(await screen.findByTestId('queued-messages')).toHaveTextContent('and check Ninis too');
    });

    // Reachable whenever a flush was interrupted: the user sees a chip,
    // types a follow-up, and the follow-up would arrive first.
    it('keeps typed order when a message is sent on top of a backlog', async () => {
      // Only the first turn is held — the flushes behind it have to be
      // able to finish, or the queue never drains past one.
      let release = () => {};
      watchTurn.mockImplementationOnce(
        () => new Promise<number | null>((resolve) => (release = () => resolve(null))),
      );

      render(<ChatClient />);
      await type('first');
      await waitFor(() => expect(sendMessage).toHaveBeenCalledTimes(1));
      await type('second');
      await type('third');

      release();

      await waitFor(() => expect(sendMessage).toHaveBeenCalledTimes(3));
      const order = sendMessage.mock.calls.map((call) => call[1]);
      expect(order).toEqual(['first', 'second', 'third']);
    });

    // The server refuses a message queued behind a parked call — the
    // tool_use would dangle while the model answered something else.
    it('holds a queued message while a confirmation is parked', async () => {
      watchTurn.mockImplementation(async (_id, _after, onEvent) => {
        onEvent({
          type: 'awaiting_confirmation',
          tool: { name: 'delete_review', input: {}, prompt: null, fingerprint: 'fp-1' },
        });
      });
      getConversation.mockResolvedValue({
        ...blank,
        state: 'awaiting_confirmation',
        pending: { name: 'delete_review', input: {}, prompt: null, fingerprint: 'fp-1' },
      });

      render(<ChatClient />);
      await type('delete my review');
      await screen.findByTestId('confirm-prompt');

      await type('actually, leave it');

      expect(await screen.findByTestId('queued-messages')).toHaveTextContent('actually, leave it');
      expect(sendMessage).toHaveBeenCalledTimes(1);
    });
  });

  // The gate is the server's. The picker only says which one to use, so
  // there is nothing here that could disagree with what actually ran.
  describe('the mode picker', () => {
    it('opens in the mode the server stored', async () => {
      getConversation.mockResolvedValue({ ...answered('ok'), mode: 'accept_edits' });

      render(<ChatClient />);
      await type('hi');

      await waitFor(() => expect(screen.getByTestId('mode-picker')).toHaveValue('accept_edits'));
    });

    it('persists a switch so it survives a reload', async () => {
      render(<ChatClient />);
      await type('hi');
      await waitFor(() => expect(sendMessage).toHaveBeenCalled());

      fireEvent.change(screen.getByTestId('mode-picker'), { target: { value: 'planning' } });

      await waitFor(() => expect(setConversationMode).toHaveBeenCalledWith('c-1', 'planning'));
    });

    it('sends the chosen mode with the turn', async () => {
      render(<ChatClient />);
      await type('hi');
      await waitFor(() => expect(sendMessage).toHaveBeenCalled());
      fireEvent.change(screen.getByTestId('mode-picker'), { target: { value: 'auto' } });

      await type('go ahead');

      await waitFor(() =>
        expect(sendMessage).toHaveBeenLastCalledWith('c-1', 'go ahead', undefined, 'auto'),
      );
    });

    // Someone in `auto` has switched off the only place a destructive
    // call stops for a human. That has to be visible without opening the
    // picker to check.
    it('says so on screen when the mode is not the default', async () => {
      render(<ChatClient />);
      await screen.findByTestId('chat-welcome');
      expect(screen.queryByTestId('mode-notice')).toBeNull();

      fireEvent.change(screen.getByTestId('mode-picker'), { target: { value: 'auto' } });

      expect(await screen.findByTestId('mode-notice')).toHaveTextContent('Never asks');
    });
  });

  it('sends a signed-out visitor to log in', async () => {
    const { NotSignedInError } = await import('../../../lib/chat');
    listConversations.mockRejectedValue(new NotSignedInError());

    render(<ChatClient />);

    await waitFor(() => expect(mockReplace).toHaveBeenCalledWith('/login?next=%2Fchat'));
  });

  // Uploaded files travel as ids, never bytes — the id has to reach the
  // model or it cannot start a scan.
  it('names an uploaded attachment and its id in the message', async () => {
    uploadAttachment.mockResolvedValue({
      id: 'signed-abc',
      filename: 'menu.jpg',
      content_type: 'image/jpeg',
      byte_size: 10,
    });
    render(<ChatClient />);
    const input = await screen.findByLabelText('Attach a menu photo or PDF');
    fireEvent.change(input, {
      target: { files: [new File(['x'], 'menu.jpg', { type: 'image/jpeg' })] },
    });

    expect(await screen.findByTestId('attachment-chips')).toHaveTextContent('menu.jpg');
    await type('read this');

    await waitFor(() =>
      expect(sendMessage).toHaveBeenCalledWith(
        'c-1',
        expect.stringContaining('attachment_id: signed-abc'),
        undefined,
        'manual',
      ),
    );
  });

  // `accept_edits` and `auto` skip the confirmation gate, so after the
  // fact is the only lever left. Whether there is anything to reverse is
  // the server's answer — it reads the tool annotations; the client just
  // renders what it is told and sends an ordinary turn.
  describe('undo', () => {
    function withUndo(canUndo: boolean): Conversation {
      return { ...answered('Removed peanut from your avoid list.'), can_undo: canUndo };
    }

    it('offers to reverse a turn that wrote', async () => {
      getConversation.mockResolvedValue(withUndo(true));
      render(<ChatClient />);
      await type('stop avoiding peanut');

      fireEvent.click(await screen.findByTestId('undo-turn'));

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith(
          'c-1',
          'Undo everything you just did.',
          undefined,
          'manual',
        ),
      );
    });

    it('stays out of the way when nothing was written', async () => {
      getConversation.mockResolvedValue(withUndo(false));
      render(<ChatClient />);
      await type('what can I eat here?');

      await screen.findByTestId('assistant-message');
      expect(screen.queryByTestId('undo-turn')).not.toBeInTheDocument();
    });

    // Mid-turn the honest control is Stop. Showing both invites undoing
    // work that is still running.
    it('does not appear while a turn is still going', async () => {
      getConversation.mockResolvedValue(withUndo(true));
      watchTurn.mockImplementation(
        () =>
          new Promise(() => {
            /* never settles: the turn is still running */
          }),
      );
      render(<ChatClient />);
      await type('stop avoiding peanut');

      expect(await screen.findByRole('button', { name: 'Stop' })).toBeInTheDocument();
      expect(screen.queryByTestId('undo-turn')).not.toBeInTheDocument();
    });
  });
});
