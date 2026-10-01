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
vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: mockReplace }),
  usePathname: () => '/chat',
}));

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

// The pane fetches menus and scans of its own; here it only has to show
// where it was pointed.
vi.mock('../_ResultsPane', () => ({
  ResultsPane: ({
    pane,
    revision,
    working,
  }: {
    pane: { kind: string; restaurant?: string | null; scan_id?: string | null } | null;
    revision: number;
    working: string | null;
  }) => (
    <div data-testid="results-pane" data-revision={revision}>
      {pane ? `${pane.kind}:${pane.restaurant ?? pane.scan_id ?? ''}` : 'empty'}
      {working ? ` working:${working}` : ''}
    </div>
  ),
}));

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

  // `capture` makes a phone open the camera and skip the photo library,
  // so a menu photographed earlier could never be attached.
  it('lets a phone attach a photo already taken, not only open the camera', async () => {
    render(<ChatClient />);

    expect(await screen.findByLabelText('Attach a menu photo or PDF')).not.toHaveAttribute(
      'capture',
    );
  });

  // The disclaimer earns its place on an empty chat, where someone is
  // about to decide how much to trust the answers, and stops earning it
  // once they are reading one — the chat sizes itself to the viewport,
  // so a permanent copy of it is four lines of a phone screen spent on
  // something already read.
  it('shows the safety disclaimer on a new chat and drops it once the chat has content', async () => {
    watchTurn.mockImplementation(async (_id, _after, onEvent) => {
      onEvent({ type: 'done', text: 'Ninis has 12 dishes you can eat.' });
    });
    getConversation.mockResolvedValue(answered('Ninis has 12 dishes you can eat.'));

    render(<ChatClient />);
    expect(await screen.findByTestId('site-disclaimer')).toHaveTextContent(/always confirm with/i);

    await type('hi');

    await waitFor(() => expect(screen.queryByTestId('site-disclaimer')).not.toBeInTheDocument());
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

    // History used to drop the sentence, so a finished turn redrew every
    // card as "Did get menu" the moment the stream closed.
    it("labels a stored card with the tool's own sentence", async () => {
      getConversation.mockResolvedValue({
        ...withTool,
        messages: withTool.messages.map((m) => ({
          ...m,
          blocks: m.blocks.map((b) =>
            b.type === 'tool_use' ? { ...b, doing: "Reading the menu at Nini's" } : b,
          ),
        })),
      });
      render(<ChatClient />);
      await type('hi');

      const card = await screen.findByTestId('tool-card');
      expect(card).toHaveTextContent("Reading the menu at Nini's");
      expect(card).not.toHaveTextContent('Did get menu');
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
  // Off until turned on; while on, every message carries a coarse fix
  // and nothing else about where the person is.
  describe('"Use my location"', () => {
    const getCurrentPosition = vi.fn();

    beforeEach(() => {
      window.localStorage.clear();
      getCurrentPosition.mockReset();
      Object.defineProperty(navigator, 'geolocation', {
        configurable: true,
        value: { getCurrentPosition },
      });
    });

    afterEach(() => {
      Object.defineProperty(navigator, 'geolocation', { configurable: true, value: undefined });
    });

    it('sends nothing until it is turned on', async () => {
      render(<ChatClient />);
      await type('hi');

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-1', 'hi', undefined, 'manual'),
      );
      expect(getCurrentPosition).not.toHaveBeenCalled();
    });

    it('sends a coarse fix with the message once on, and remembers the choice', async () => {
      getCurrentPosition.mockImplementation((ok: PositionCallback) =>
        ok({
          coords: { latitude: 37.27531, longitude: -107.88012, accuracy: 18.6 },
        } as GeolocationPosition),
      );
      render(<ChatClient />);
      await screen.findByTestId('chat-welcome');

      const toggle = screen.getByRole('button', { name: 'Use my location' });
      fireEvent.click(toggle);
      await waitFor(() => expect(toggle).toHaveAttribute('aria-pressed', 'true'));
      await type('what is near me');

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith(
          'c-1',
          'what is near me',
          { location: { lat: 37.275, lng: -107.88, accuracy_m: 19 } },
          'manual',
        ),
      );
      expect(window.localStorage.getItem('bw_chat_use_location')).toBe('on');
    });

    // A reload with the pin remembered on starts a fix that can land
    // after the first message is typed. That message must not go out
    // without the location the lit pin promises.
    it('holds a send briefly for a first fix that is on its way', async () => {
      getCurrentPosition.mockImplementation((ok: PositionCallback) =>
        setTimeout(
          () =>
            ok({
              coords: { latitude: 37.2751, longitude: -107.8801, accuracy: 30 },
              timestamp: Date.now(),
            } as GeolocationPosition),
          50,
        ),
      );
      window.localStorage.setItem('bw_chat_use_location', 'on');
      render(<ChatClient />);
      await type('pizza near me');

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith(
          'c-1',
          'pizza near me',
          { location: { lat: 37.275, lng: -107.88, accuracy_m: 30 } },
          'manual',
        ),
      );
    });

    it('retries on a tap after a timeout instead of turning off', async () => {
      getCurrentPosition.mockImplementationOnce(
        (_ok: PositionCallback, fail: PositionErrorCallback) =>
          fail({ code: 3, PERMISSION_DENIED: 1 } as GeolocationPositionError),
      );
      render(<ChatClient />);
      await screen.findByTestId('chat-welcome');

      fireEvent.click(screen.getByRole('button', { name: 'Use my location' }));
      expect(await screen.findByText(/Could not get your location/)).toBeInTheDocument();
      fireEvent.click(screen.getByRole('button', { name: 'Use my location' }));

      expect(getCurrentPosition).toHaveBeenCalledTimes(2);
      expect(window.localStorage.getItem('bw_chat_use_location')).toBe('on');
    });

    it('says so and stays off when the browser refuses', async () => {
      getCurrentPosition.mockImplementation((_ok: PositionCallback, fail: PositionErrorCallback) =>
        fail({ code: 1, PERMISSION_DENIED: 1 } as GeolocationPositionError),
      );
      render(<ChatClient />);
      await screen.findByTestId('chat-welcome');

      fireEvent.click(screen.getByRole('button', { name: 'Use my location' }));

      expect(await screen.findByText(/Location is blocked/)).toBeInTheDocument();
      expect(window.localStorage.getItem('bw_chat_use_location')).toBeNull();
      await type('hi');
      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-1', 'hi', undefined, 'manual'),
      );
    });
  });

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

  // Deleting a chat cannot be undone, and the × sits right next to the
  // title people click to open it. One stray click must not cost a
  // conversation.
  describe('deleting a chat from the sidebar', () => {
    beforeEach(() => {
      listConversations.mockResolvedValue({
        conversations: [{ ...blank, id: 'c-old', title: 'Add city Riverton Utah' }],
      });
      // Like the server: once deleted, the list stops returning it.
      deleteConversation.mockImplementation(async () => {
        listConversations.mockResolvedValue({ conversations: [] });
      });
    });

    it('asks before deleting', async () => {
      render(<ChatClient />);
      fireEvent.click(await screen.findByRole('button', { name: 'Delete Add city Riverton Utah' }));

      expect(deleteConversation).not.toHaveBeenCalled();
      expect(screen.getByText('Delete this chat?')).toBeInTheDocument();

      fireEvent.click(screen.getByRole('button', { name: 'Delete' }));

      await waitFor(() => expect(deleteConversation).toHaveBeenCalledWith('c-old'));
      await waitFor(() =>
        expect(screen.queryByText('Add city Riverton Utah')).not.toBeInTheDocument(),
      );
    });

    // Deleting the open chat mid-turn takes its run with it, so the watcher
    // and the teardown refresh both fail. Neither is news to the person
    // who just deleted it — the new blank chat must not open on a 404.
    it('stays quiet when the chat deleted was mid-turn', async () => {
      listConversations.mockResolvedValue({ conversations: [{ ...blank, title: 'Busy chat' }] });
      let dropWatch: (e: Error) => void = () => {};
      watchTurn.mockImplementation(
        () =>
          new Promise((_, reject) => {
            dropWatch = reject;
          }),
      );
      render(<ChatClient />);
      await type('hi');
      await screen.findByRole('button', { name: 'Stop' });

      fireEvent.click(screen.getByRole('button', { name: 'Delete Busy chat' }));
      fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
      await waitFor(() => expect(deleteConversation).toHaveBeenCalledWith('c-1'));

      getConversation.mockRejectedValue(new Error('Not found'));
      dropWatch(new Error('Not found'));

      await waitFor(() => expect(screen.queryByRole('button', { name: 'Stop' })).toBeNull());
      expect(screen.queryByTestId('chat-error')).toBeNull();
    });

    // The real mid-stream shape: the server reports the vanished run as an
    // error event and then closes the stream normally.
    it('ignores the error event a deleted run reports', async () => {
      listConversations.mockResolvedValue({ conversations: [{ ...blank, title: 'Busy chat' }] });
      let finish: (e: ChatEvent | null) => void = () => {};
      watchTurn.mockImplementation(
        async (_id: string, _after: number, onEvent: (e: ChatEvent) => void) =>
          new Promise<null>((resolve) => {
            finish = (event) => {
              if (event) onEvent(event);
              resolve(null);
            };
          }),
      );
      render(<ChatClient />);
      await type('hi');
      await screen.findByRole('button', { name: 'Stop' });

      fireEvent.click(screen.getByRole('button', { name: 'Delete Busy chat' }));
      fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
      await waitFor(() => expect(deleteConversation).toHaveBeenCalledWith('c-1'));

      finish({ type: 'error', message: 'Conversation not found' });

      await waitFor(() => expect(screen.queryByRole('button', { name: 'Stop' })).toBeNull());
      expect(screen.queryByTestId('chat-error')).toBeNull();
    });

    // A delete that fails leaves the chat in place, so the turn it
    // interrupted has to settle the way it normally would.
    it('still settles the turn when the delete fails', async () => {
      listConversations.mockResolvedValue({ conversations: [{ ...blank, title: 'Busy chat' }] });
      let failDelete: (e: Error) => void = () => {};
      deleteConversation.mockImplementation(
        () =>
          new Promise((_, reject) => {
            failDelete = reject;
          }),
      );
      let dropWatch: (e: Error) => void = () => {};
      watchTurn.mockImplementation(
        () =>
          new Promise((_, reject) => {
            dropWatch = reject;
          }),
      );
      render(<ChatClient />);
      await type('hi');
      await screen.findByRole('button', { name: 'Stop' });

      fireEvent.click(screen.getByRole('button', { name: 'Delete Busy chat' }));
      fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
      await waitFor(() => expect(deleteConversation).toHaveBeenCalledWith('c-1'));
      getConversation.mockClear();
      getConversation.mockResolvedValue({ ...blank, title: 'Busy chat' });

      dropWatch(new Error('Connection lost'));
      failDelete(new Error('Could not delete'));

      await waitFor(() => expect(getConversation).toHaveBeenCalledWith('c-1'));
      expect(within(screen.getByTestId('chat-history')).getByText('Busy chat')).toBeInTheDocument();
      // The delete's failure, not the dropped stream: the chat the person
      // tried to remove is still there, and that is what they need to know.
      expect(await screen.findByTestId('chat-error')).toHaveTextContent('Could not delete');
    });

    // The turn can end, and its teardown refetch be in flight, just before
    // the delete lands. A late answer must not put the chat back.
    it('does not bring back a chat deleted while it was being refetched', async () => {
      listConversations.mockResolvedValue({ conversations: [{ ...blank, title: 'Busy chat' }] });
      let answer: (c: Conversation) => void = () => {};
      render(<ChatClient />);
      await screen.findByText('Busy chat');
      getConversation.mockImplementation(
        () =>
          new Promise((resolve) => {
            answer = resolve;
          }),
      );
      fireEvent.click(screen.getByText('Busy chat'));
      await waitFor(() => expect(getConversation).toHaveBeenCalledWith('c-1'));

      fireEvent.click(screen.getByRole('button', { name: 'Delete Busy chat' }));
      fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
      await waitFor(() => expect(screen.queryByText('Busy chat')).toBeNull());

      answer({ ...blank, title: 'Busy chat', messages: [] });

      await new Promise((r) => setTimeout(r, 0));
      expect(screen.queryByText('Busy chat')).toBeNull();
    });

    it('does not re-queue a message whose chat was deleted before it was sent', async () => {
      listConversations.mockResolvedValue({ conversations: [{ ...blank, title: 'Busy chat' }] });
      let refuse: (e: Error) => void = () => {};
      sendMessage.mockImplementation(
        () =>
          new Promise((_, reject) => {
            refuse = reject;
          }),
      );
      render(<ChatClient />);
      await type('hi');
      await screen.findByRole('button', { name: 'Stop' });

      fireEvent.click(screen.getByRole('button', { name: 'Delete Busy chat' }));
      fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
      await waitFor(() => expect(deleteConversation).toHaveBeenCalledWith('c-1'));
      refuse(new Error('Not found'));

      await waitFor(() => expect(screen.queryByRole('button', { name: 'Stop' })).toBeNull());
      expect(screen.queryByTestId('queued-messages')).toBeNull();
    });

    // The blank chat that replaces a deleted one is usable at once, not
    // after the dead turn's stream gets around to closing.
    it('sends from the replacement chat while the deleted turn is still closing', async () => {
      listConversations.mockResolvedValue({ conversations: [{ ...blank, title: 'Busy chat' }] });
      let finish: () => void = () => {};
      watchTurn.mockImplementationOnce(
        () =>
          new Promise<null>((resolve) => {
            finish = () => resolve(null);
          }),
      );
      render(<ChatClient />);
      await type('hi');
      await screen.findByRole('button', { name: 'Stop' });

      fireEvent.click(screen.getByRole('button', { name: 'Delete Busy chat' }));
      fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
      await waitFor(() => expect(screen.queryByRole('button', { name: 'Stop' })).toBeNull());

      createConversation.mockResolvedValue({ ...blank, id: 'c-2' });
      await type('next question');

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-2', 'next question', undefined, 'manual'),
      );
      finish();
      expect(screen.queryByTestId('queued-messages')).toBeNull();
    });

    it('keeps the chat when the person cancels', async () => {
      render(<ChatClient />);
      fireEvent.click(await screen.findByRole('button', { name: 'Delete Add city Riverton Utah' }));
      fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));

      expect(deleteConversation).not.toHaveBeenCalled();
      expect(screen.getByText('Add city Riverton Utah')).toBeInTheDocument();
    });
  });
  // A turn belongs to the chat it runs in, not to whatever is on screen.
  // These pin that when the person moves between chats mid-turn.
  describe('a turn that keeps running after the person moves on', () => {
    const busy = { ...blank, id: 'c-1', title: 'Busy chat' };
    const other = { ...blank, id: 'c-2', title: 'Other chat' };
    let finish: () => void = () => {};

    beforeEach(() => {
      listConversations.mockResolvedValue({ conversations: [busy, other] });
      getConversation.mockImplementation(async (id: string) => ({
        ...(id === 'c-2' ? other : busy),
        messages: [],
      }));
      deleteConversation.mockResolvedValue(undefined);
      watchTurn.mockImplementationOnce(
        () =>
          new Promise<null>((resolve) => {
            finish = () => resolve(null);
          }),
      );
    });

    async function startTurnThenOpenOther() {
      render(<ChatClient />);
      await type('hi');
      await screen.findByRole('button', { name: 'Stop' });
      fireEvent.click(screen.getByText('Other chat'));
      await waitFor(() => expect(getConversation).toHaveBeenCalledWith('c-2'));
    }

    it('does not pull the person back when the turn they left finishes', async () => {
      await startTurnThenOpenOther();

      finish();

      await waitFor(() => expect(screen.queryByRole('button', { name: 'Stop' })).toBeNull());
      expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Other chat');
    });

    it('sends what was queued on screen when the running chat is deleted', async () => {
      await startTurnThenOpenOther();
      await type('for the other chat');
      expect(sendMessage).toHaveBeenCalledTimes(1);

      fireEvent.click(screen.getByRole('button', { name: 'Delete Busy chat' }));
      fireEvent.click(screen.getByRole('button', { name: 'Delete' }));

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-2', 'for the other chat', undefined, 'manual'),
      );
      finish();
    });

    // A finished turn still holds the page while it refetches. A message
    // typed into that gap waits and then goes, instead of starting a turn
    // the refetch would overwrite with the snapshot from before it.
    it('queues a message typed while the finished turn is still refetching', async () => {
      render(<ChatClient />);
      await type('hi');
      await screen.findByRole('button', { name: 'Stop' });
      let land: () => void = () => {};
      getConversation.mockImplementation(
        () =>
          new Promise((resolve) => {
            land = () => resolve({ ...busy, messages: [] });
          }),
      );

      finish();
      await waitFor(() => expect(getConversation).toHaveBeenCalledWith('c-1'));
      await type('next');
      expect(sendMessage).toHaveBeenCalledTimes(1);
      expect(screen.getByTestId('queued-messages')).toBeInTheDocument();

      land();
      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-1', 'next', undefined, 'manual'),
      );
    });

    // A message that never reached the server is normally put back as a
    // chip. If its chat is deleted before that happens, there is nowhere
    // for it to go — and a chip that can never drain would hold up every
    // message typed after it.
    it('drops a failed message whose chat was deleted instead of re-queueing it', async () => {
      render(<ChatClient />);
      fireEvent.click(await screen.findByText('Busy chat'));
      await screen.findByRole('heading', { level: 1, name: 'Busy chat' });

      sendMessage.mockRejectedValueOnce(new Error('Could not send'));
      let land: () => void = () => {};
      getConversation.mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            land = () => resolve({ ...busy, messages: [] });
          }),
      );
      await type('hi');
      await waitFor(() => expect(getConversation).toHaveBeenCalledTimes(2));

      fireEvent.click(screen.getByRole('button', { name: 'Delete Busy chat' }));
      fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
      await waitFor(() => expect(deleteConversation).toHaveBeenCalledWith('c-1'));
      land();

      await waitFor(() =>
        expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('New chat'),
      );
      await new Promise((r) => setTimeout(r, 0));
      expect(screen.queryByTestId('queued-messages')).toBeNull();

      createConversation.mockResolvedValue({ ...blank, id: 'c-9' });
      await type('fresh start');
      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-9', 'fresh start', undefined, 'manual'),
      );
    });

    it('keeps the chat the person opened while a new one was still being created', async () => {
      let created: () => void = () => {};
      createConversation.mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            created = () => resolve({ ...blank, id: 'c-new', title: 'Brand new' });
          }),
      );
      render(<ChatClient />);
      await type('hi');
      fireEvent.click(await screen.findByText('Other chat'));
      await screen.findByRole('heading', { level: 1, name: 'Other chat' });

      created();

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-new', 'hi', undefined, 'manual'),
      );
      expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Other chat');
      finish();
      await waitFor(() => expect(screen.queryByTestId('live-turn')).toBeNull());
    });

    it('clears a deleted chat that is still drawn while another is opening', async () => {
      render(<ChatClient />);
      fireEvent.click(await screen.findByText('Busy chat'));
      await screen.findByRole('heading', { level: 1, name: 'Busy chat' });
      getConversation.mockImplementationOnce(() => new Promise(() => {}));
      fireEvent.click(screen.getByText('Other chat'));

      fireEvent.click(screen.getByRole('button', { name: 'Delete Busy chat' }));
      fireEvent.click(screen.getByRole('button', { name: 'Delete' }));

      await waitFor(() =>
        expect(screen.queryByRole('heading', { level: 1, name: 'Busy chat' })).toBeNull(),
      );
    });

    it('drops a failed first message whose new chat was deleted during the refetch', async () => {
      sendMessage.mockRejectedValueOnce(new Error('Could not send'));
      let land: () => void = () => {};
      getConversation.mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            land = () => resolve({ ...busy, messages: [] });
          }),
      );
      render(<ChatClient />);
      await type('hi');
      await waitFor(() => expect(getConversation).toHaveBeenCalledWith('c-1'));

      fireEvent.click(screen.getByRole('button', { name: 'Delete Busy chat' }));
      fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
      await waitFor(() => expect(deleteConversation).toHaveBeenCalledWith('c-1'));
      land();

      await new Promise((r) => setTimeout(r, 0));
      await waitFor(() => expect(screen.queryByTestId('queued-messages')).toBeNull());
    });

    it('keeps the drawn chat working after opening another one fails', async () => {
      render(<ChatClient />);
      fireEvent.click(await screen.findByText('Busy chat'));
      await screen.findByRole('heading', { level: 1, name: 'Busy chat' });
      getConversation.mockRejectedValueOnce(new Error('Could not open'));
      fireEvent.click(screen.getByText('Other chat'));
      await screen.findByTestId('chat-error');

      await type('still here');

      expect(await screen.findByText('still here')).toBeInTheDocument();
      finish();
    });

    it('re-queues a failed first message for the chat it created, not the one on screen', async () => {
      let created: () => void = () => {};
      createConversation.mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            created = () => resolve({ ...blank, id: 'c-new' });
          }),
      );
      sendMessage.mockRejectedValueOnce(new Error('Could not send'));
      render(<ChatClient />);
      await type('first');
      fireEvent.click(await screen.findByText('Other chat'));
      await screen.findByRole('heading', { level: 1, name: 'Other chat' });
      created();
      await waitFor(() => expect(sendMessage).toHaveBeenCalledTimes(1));

      await type('for other');

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-2', 'for other', undefined, 'manual'),
      );
      expect(sendMessage).not.toHaveBeenCalledWith('c-2', 'first', undefined, 'manual');
    });

    it('stays busy until the finished turn has let go of the page', async () => {
      render(<ChatClient />);
      await type('hi');
      await screen.findByRole('button', { name: 'Stop' });
      getConversation.mockImplementationOnce(() => new Promise(() => {}));

      finish();
      await waitFor(() => expect(getConversation).toHaveBeenCalledWith('c-1'));

      expect(screen.getByRole('button', { name: 'Stop' })).toBeInTheDocument();
    });

    // Switching away is not cancelling: a failed first message waits for
    // the chat it created and goes as soon as the person opens that chat.
    it('retries a failed first message when its chat is opened', async () => {
      let created: () => void = () => {};
      createConversation.mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            created = () => resolve({ ...blank, id: 'c-new', title: 'Brand new' });
          }),
      );
      sendMessage.mockRejectedValueOnce(new Error('Could not send'));
      render(<ChatClient />);
      await type('first');
      fireEvent.click(await screen.findByText('Other chat'));
      await screen.findByRole('heading', { level: 1, name: 'Other chat' });
      getConversation.mockImplementation(async (id: string) => ({
        ...(id === 'c-new' ? { ...blank, id: 'c-new', title: 'Brand new' } : other),
        messages: [],
      }));
      listConversations.mockResolvedValue({
        conversations: [{ ...blank, id: 'c-new', title: 'Brand new' }, busy, other],
      });
      created();
      await waitFor(() => expect(sendMessage).toHaveBeenCalledTimes(1));
      await waitFor(() => expect(screen.queryByTestId('live-turn')).toBeNull());

      fireEvent.click(await screen.findByText('Brand new'));

      // The retry, not the failed attempt: that one was also (c-new, first).
      await waitFor(() => expect(sendMessage).toHaveBeenCalledTimes(2));
      expect(sendMessage).toHaveBeenLastCalledWith('c-new', 'first', undefined, 'manual');
    });

    it('keeps a chat’s queued message through a switch away and back', async () => {
      render(<ChatClient />);
      await type('hi');
      await screen.findByRole('button', { name: 'Stop' });
      await type('later');
      expect(screen.getByTestId('queued-messages')).toHaveTextContent('later');

      fireEvent.click(screen.getByText('Other chat'));
      await screen.findByRole('heading', { level: 1, name: 'Other chat' });
      expect(screen.queryByTestId('queued-messages')).toBeNull();

      fireEvent.click(within(screen.getByTestId('chat-history')).getByText('Busy chat'));
      await screen.findByRole('heading', { level: 1, name: 'Busy chat' });
      expect(screen.getByTestId('queued-messages')).toHaveTextContent('later');

      finish();
      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-1', 'later', undefined, 'manual'),
      );
    });

    // Two blank chats in a row are two conversations. A message queued in
    // the second must not be re-tagged to the first when that one finishes
    // being created.
    it('keeps a message typed in a second blank chat out of the first one', async () => {
      let createA: () => void = () => {};
      createConversation
        .mockImplementationOnce(
          () =>
            new Promise((resolve) => {
              createA = () => resolve({ ...blank, id: 'c-a', title: 'Chat A' });
            }),
        )
        .mockResolvedValueOnce({ ...blank, id: 'c-b', title: 'Chat B' });
      getConversation.mockImplementation(async (id: string) => ({
        ...blank,
        id,
        title: id === 'c-a' ? 'Chat A' : 'Chat B',
        messages: [],
      }));
      render(<ChatClient />);
      await type('for A');
      fireEvent.click(screen.getByRole('button', { name: 'New chat' }));
      await type('for B');

      createA();
      await waitFor(() => expect(watchTurn).toHaveBeenCalled());
      finish();

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-b', 'for B', undefined, 'manual'),
      );
      expect(sendMessage).toHaveBeenCalledWith('c-a', 'for A', undefined, 'manual');
      expect(sendMessage).not.toHaveBeenCalledWith('c-a', 'for B', undefined, 'manual');
    });

    // A confirmation gate the person chose for one chat must not be
    // swapped for another chat's because of when the queue drains.
    it("sends a reopened chat's queued message under that chat's own mode", async () => {
      getConversation.mockImplementation(async (id: string) =>
        id === 'c-2'
          ? { ...other, mode: 'manual', messages: [] }
          : { ...busy, mode: 'auto', messages: [] },
      );
      render(<ChatClient />);
      fireEvent.click(await screen.findByText('Busy chat'));
      await screen.findByRole('heading', { level: 1, name: 'Busy chat' });
      await type('hi');
      await screen.findByRole('button', { name: 'Stop' });

      fireEvent.click(screen.getByText('Other chat'));
      await screen.findByRole('heading', { level: 1, name: 'Other chat' });
      await type('queued for other');
      fireEvent.click(within(screen.getByTestId('chat-history')).getByText('Busy chat'));
      await screen.findByRole('heading', { level: 1, name: 'Busy chat' });
      finish();
      await waitFor(() => expect(screen.queryByRole('button', { name: 'Stop' })).toBeNull());

      fireEvent.click(screen.getByText('Other chat'));

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-2', 'queued for other', undefined, 'manual'),
      );
    });

    it('drains the blank chat on screen when an earlier chat fails to be created', async () => {
      let failA: () => void = () => {};
      createConversation
        .mockImplementationOnce(
          () =>
            new Promise((_, reject) => {
              failA = () => reject(new Error('Could not start a chat'));
            }),
        )
        .mockResolvedValueOnce({ ...blank, id: 'c-b', title: 'Chat B' });
      render(<ChatClient />);
      await type('for A');
      fireEvent.click(screen.getByRole('button', { name: 'New chat' }));
      await type('for B');

      failA();

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-b', 'for B', undefined, 'manual'),
      );
      expect(screen.queryByText('for A')).toBeNull();
    });

    it('keeps the order of a blank chat’s messages when its creation fails', async () => {
      let failA: () => void = () => {};
      createConversation.mockImplementationOnce(
        () =>
          new Promise((_, reject) => {
            failA = () => reject(new Error('Could not start a chat'));
          }),
      );
      render(<ChatClient />);
      await type('first');
      await type('second');

      failA();

      await waitFor(() =>
        expect(screen.getByTestId('queued-messages')).toHaveTextContent(/first[\s\S]*second/),
      );
      expect(sendMessage).not.toHaveBeenCalled();
    });

    it('drains an opened chat when the blank chat left behind fails to be created', async () => {
      let failA: () => void = () => {};
      createConversation.mockImplementationOnce(
        () =>
          new Promise((_, reject) => {
            failA = () => reject(new Error('Could not start a chat'));
          }),
      );
      render(<ChatClient />);
      await type('for A');
      fireEvent.click(await screen.findByText('Other chat'));
      await screen.findByRole('heading', { level: 1, name: 'Other chat' });
      await type('for other');

      failA();

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-2', 'for other', undefined, 'manual'),
      );
      expect(screen.queryByTestId('queued-messages')).toBeNull();
    });

    it('sends a message typed while a chat is opening to that chat once it arrives', async () => {
      let arrive: () => void = () => {};
      render(<ChatClient />);
      getConversation.mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            arrive = () => resolve({ ...other, messages: [] });
          }),
      );
      fireEvent.click(await screen.findByText('Other chat'));
      await type('early');
      expect(sendMessage).not.toHaveBeenCalled();

      arrive();

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-2', 'early', undefined, 'manual'),
      );
    });

    it('drains the chat it falls back to when an open fails', async () => {
      render(<ChatClient />);
      fireEvent.click(await screen.findByText('Busy chat'));
      await screen.findByRole('heading', { level: 1, name: 'Busy chat' });
      await type('hi');
      await screen.findByRole('button', { name: 'Stop' });
      await type('queued');
      let refuse: () => void = () => {};
      getConversation.mockImplementationOnce(
        () =>
          new Promise((_, reject) => {
            refuse = () => reject(new Error('Could not open'));
          }),
      );
      fireEvent.click(screen.getByText('Other chat'));
      finish();
      await waitFor(() => expect(screen.queryByRole('button', { name: 'Stop' })).toBeNull());

      refuse();

      await waitFor(() =>
        expect(sendMessage).toHaveBeenCalledWith('c-1', 'queued', undefined, 'manual'),
      );
    });

    it('keeps a blank chat’s queued message when opening another chat fails', async () => {
      render(<ChatClient />);
      fireEvent.click(await screen.findByText('Busy chat'));
      await screen.findByRole('heading', { level: 1, name: 'Busy chat' });
      await type('hi');
      await screen.findByRole('button', { name: 'Stop' });
      fireEvent.click(screen.getByRole('button', { name: 'New chat' }));
      await type('in the blank chat');
      getConversation.mockRejectedValueOnce(new Error('Could not open'));

      fireEvent.click(screen.getByText('Other chat'));
      await screen.findByTestId('chat-error');

      expect(screen.getByTestId('queued-messages')).toHaveTextContent('in the blank chat');
      finish();
    });

    it('keeps the running turn when a different chat is deleted', async () => {
      await startTurnThenOpenOther();

      fireEvent.click(screen.getByRole('button', { name: 'Delete Other chat' }));
      fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
      await waitFor(() => expect(deleteConversation).toHaveBeenCalledWith('c-2'));

      expect(screen.getByRole('button', { name: 'Stop' })).toBeInTheDocument();
      finish();
      await waitFor(() => expect(screen.queryByRole('button', { name: 'Stop' })).toBeNull());
    });
  });

  describe('the results pane', () => {
    it('points the pane at what the turn acted on, and keeps it after the refetch', async () => {
      watchTurn.mockImplementation(async (_id, _after, onEvent) => {
        onEvent({
          type: 'tool_use',
          name: 'get_menu',
          input: { restaurant: 'ninis' },
          doing: 'Reading the menu at ninis',
        });
        onEvent({ type: 'pane', pane: { kind: 'menu', restaurant: 'ninis' } });
        onEvent({ type: 'tool_result', name: 'get_menu', ok: true });
        onEvent({ type: 'done', text: 'Here you go.' });
      });
      getConversation.mockResolvedValue({
        ...answered('Here you go.'),
        pane: { kind: 'menu', restaurant: 'ninis' },
      });

      render(<ChatClient />);
      expect(screen.getByTestId('results-pane')).toHaveTextContent('empty');
      await type('what can I eat at ninis');

      await waitFor(() =>
        expect(screen.getByTestId('results-pane')).toHaveTextContent('menu:ninis'),
      );
      // The phone-width toggle appears only once there is something to show.
      expect(screen.getByTestId('pane-toggle')).toBeInTheDocument();
    });

    it('restores the stored pane when a chat is opened, and clears it for a new one', async () => {
      listConversations.mockResolvedValue({
        conversations: [{ ...blank, id: 'c-9', title: 'Ninis', messages: undefined }],
      });
      getConversation.mockResolvedValue({
        ...answered('12 dishes.'),
        id: 'c-9',
        pane: { kind: 'scan', scan_id: 'run-1' },
      });

      render(<ChatClient />);
      fireEvent.click(await screen.findByRole('button', { name: 'Ninis' }));

      await waitFor(() =>
        expect(screen.getByTestId('results-pane')).toHaveTextContent('scan:run-1'),
      );

      fireEvent.click(screen.getByRole('button', { name: 'New chat' }));
      expect(screen.getByTestId('results-pane')).toHaveTextContent('empty');
    });

    it('counts every live pane event, and not the stored copy adopted after the turn', async () => {
      watchTurn.mockImplementation(async (_id, _after, onEvent) => {
        onEvent({ type: 'pane', pane: { kind: 'scan', scan_id: 'run-1' } });
        onEvent({ type: 'pane', pane: { kind: 'scan', scan_id: 'run-1' } });
        onEvent({ type: 'done', text: 'Accepted both.' });
        // Over, not dropped — `undefined` would read as a reconnect and
        // replay these twenty times.
        return null;
      });
      getConversation.mockResolvedValue({
        ...answered('Accepted both.'),
        pane: { kind: 'scan', scan_id: 'run-1' },
      });

      render(<ChatClient />);
      expect(screen.getByTestId('results-pane')).toHaveAttribute('data-revision', '0');
      await type('accept them all');

      await waitFor(() => expect(getConversation).toHaveBeenCalled());
      await waitFor(() =>
        expect(screen.getByTestId('results-pane')).toHaveAttribute('data-revision', '2'),
      );
    });

    // Two chats may point at the same menu. The second is still fetched
    // again on open: another turn — or another tab — may have changed the
    // filter since the first drew it.
    it('looks again on open even when the next chat points where the last one did', async () => {
      listConversations.mockResolvedValue({
        conversations: [
          { ...blank, id: 'c-1', title: 'First', messages: undefined },
          { ...blank, id: 'c-2', title: 'Second', messages: undefined },
        ],
      });
      getConversation.mockImplementation(async (id: string) => ({
        ...answered('menu'),
        id,
        pane: { kind: 'menu', restaurant: 'ninis' },
      }));

      render(<ChatClient />);
      fireEvent.click(await screen.findByRole('button', { name: 'First' }));
      await waitFor(() =>
        expect(screen.getByTestId('results-pane')).toHaveAttribute('data-revision', '1'),
      );

      fireEvent.click(screen.getByRole('button', { name: 'Second' }));

      await waitFor(() =>
        expect(screen.getByTestId('results-pane')).toHaveAttribute('data-revision', '2'),
      );
      expect(screen.getByTestId('results-pane')).toHaveTextContent('menu:ninis');
    });

    // A write's `pane` event can be lost with the connection. The stored
    // pane the refetch hands back is the same reference, so it has to be
    // made to look again by the turn, not by the value.
    it('makes the pane look again when a turn ran tools but its pane event never arrived', async () => {
      watchTurn.mockImplementation(async (_id, _after, onEvent) => {
        onEvent({ type: 'tool_use', name: 'set_strictness', input: { strictness: 'strict' } });
        throw new Error('Lost the connection to that turn.');
      });
      getConversation.mockResolvedValue({
        ...answered('Strict now.'),
        pane: { kind: 'menu', restaurant: 'ninis' },
      });

      render(<ChatClient />);
      await type('make it strict');

      await waitFor(() =>
        expect(screen.getByTestId('results-pane')).toHaveAttribute('data-revision', '1'),
      );
      expect(screen.getByTestId('results-pane')).toHaveTextContent('menu:ninis');
    });

    it('is not fooled by a pane event from an earlier tool in the same turn', async () => {
      watchTurn.mockImplementation(async (_id, _after, onEvent) => {
        onEvent({ type: 'tool_use', name: 'get_menu', input: { restaurant: 'ninis' } });
        onEvent({ type: 'pane', pane: { kind: 'menu', restaurant: 'ninis' } });
        onEvent({ type: 'tool_result', name: 'get_menu', ok: true });
        onEvent({ type: 'tool_use', name: 'set_strictness', input: { strictness: 'strict' } });
        throw new Error('Lost the connection to that turn.');
      });
      getConversation.mockResolvedValue({
        ...answered('Strict now.'),
        pane: { kind: 'menu', restaurant: 'ninis' },
      });

      render(<ChatClient />);
      await type('read ninis then make it strict');

      // One bump from the menu's own event, one from the lost one.
      await waitFor(() =>
        expect(screen.getByTestId('results-pane')).toHaveAttribute('data-revision', '2'),
      );
    });

    it('leaves the revision alone after a turn that ran no tools', async () => {
      watchTurn.mockImplementation(async (_id, _after, onEvent) => {
        onEvent({ type: 'done', text: 'Hi.' });
        return null;
      });
      getConversation.mockResolvedValue({
        ...answered('Hi.'),
        pane: { kind: 'menu', restaurant: 'ninis' },
      });

      render(<ChatClient />);
      await type('hi');

      await waitFor(() =>
        expect(screen.getByTestId('results-pane')).toHaveTextContent('menu:ninis'),
      );
      expect(screen.getByTestId('results-pane')).toHaveAttribute('data-revision', '0');
    });

    it('keeps the live pane when the refetch says nothing about one', async () => {
      watchTurn.mockImplementation(async (_id, _after, onEvent) => {
        onEvent({ type: 'pane', pane: { kind: 'menu', restaurant: 'ninis' } });
        onEvent({ type: 'done', text: 'Here you go.' });
      });
      // An API that predates the field — the web deploys first.
      getConversation.mockResolvedValue(answered('Here you go.'));

      render(<ChatClient />);
      await type('what can I eat at ninis');

      await waitFor(() =>
        expect(screen.getByTestId('results-pane')).toHaveTextContent('menu:ninis'),
      );
      await waitFor(() => expect(getConversation).toHaveBeenCalled());
      expect(screen.getByTestId('results-pane')).toHaveTextContent('menu:ninis');
    });

    it('brings the transcript back when another chat is opened with the pane showing', async () => {
      listConversations.mockResolvedValue({
        conversations: [{ ...blank, id: 'c-9', title: 'Other', messages: undefined }],
      });
      getConversation.mockResolvedValueOnce({
        ...answered('first'),
        pane: { kind: 'menu', restaurant: 'ninis' },
      });
      getConversation.mockResolvedValueOnce({ ...answered('second'), id: 'c-9', pane: null });
      watchTurn.mockImplementation(async (_id, _after, onEvent) => {
        onEvent({ type: 'done', text: 'first' });
      });

      render(<ChatClient />);
      await type('hi');
      fireEvent.click(await screen.findByTestId('pane-toggle'));
      // Under `lg` the pane takes the transcript's column.
      expect(screen.getByRole('main')).toHaveClass('hidden');

      fireEvent.click(screen.getByRole('button', { name: 'Other' }));

      await waitFor(() => expect(screen.getByTestId('results-pane')).toHaveTextContent('empty'));
      expect(screen.getByRole('main')).not.toHaveClass('hidden');
    });

    it('hands the pane the running tool’s sentence while it runs', async () => {
      let finish: () => void = () => {};
      watchTurn.mockImplementation(
        (_id: string, _after: number, onEvent: (e: ChatEvent) => void) =>
          new Promise<null>((resolve) => {
            onEvent({
              type: 'tool_use',
              name: 'get_menu',
              input: {},
              doing: 'Reading the menu at ninis',
            });
            finish = () => {
              onEvent({ type: 'tool_result', name: 'get_menu', ok: true });
              onEvent({ type: 'done', text: 'ok' });
              resolve(null);
            };
          }),
      );

      render(<ChatClient />);
      await type('hi');

      await waitFor(() =>
        expect(screen.getByTestId('results-pane')).toHaveTextContent(
          'working:Reading the menu at ninis',
        ),
      );
      finish();
      await waitFor(() =>
        expect(screen.getByTestId('results-pane')).not.toHaveTextContent('working:'),
      );
    });
  });
});
