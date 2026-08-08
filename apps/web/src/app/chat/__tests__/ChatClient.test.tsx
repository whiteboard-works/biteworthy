import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
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
const streamTurn = vi.fn();
const streamConfirm = vi.fn();
const uploadAttachment = vi.fn();

vi.mock('../../../lib/chat', async () => {
  const actual = await vi.importActual<typeof import('../../../lib/chat')>('../../../lib/chat');
  return {
    ...actual,
    listConversations: () => listConversations(),
    createConversation: () => createConversation(),
    getConversation: (id: string) => getConversation(id),
    deleteConversation: (id: string) => deleteConversation(id),
    streamTurn: (id: string, text: string, onEvent: (e: ChatEvent) => void) =>
      streamTurn(id, text, onEvent),
    streamConfirm: (
      id: string,
      ok: boolean,
      fingerprint: string | null,
      onEvent: (e: ChatEvent) => void,
    ) => streamConfirm(id, ok, fingerprint, onEvent),
    uploadAttachment: (file: File) => uploadAttachment(file),
  };
});

const { ChatClient } = await import('../_ChatClient');

const blank: Conversation = {
  id: 'c-1',
  title: null,
  state: 'active',
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
});

afterEach(() => {
  vi.clearAllMocks();
});

async function type(text: string) {
  fireEvent.change(await screen.findByLabelText('Message'), { target: { value: text } });
  fireEvent.click(screen.getByText('Send'));
}

describe('ChatClient', () => {
  it('opens on a prompt for what to ask', async () => {
    render(<ChatClient />);

    expect(await screen.findByTestId('chat-welcome')).toBeInTheDocument();
  });

  it('creates a conversation on the first message and streams the reply', async () => {
    streamTurn.mockImplementation(async (_id, _text, onEvent) => {
      onEvent({ type: 'text_delta', text: 'Ninis has 12 dishes you can eat.' });
      onEvent({ type: 'done', text: 'Ninis has 12 dishes you can eat.' });
    });
    getConversation.mockResolvedValue(answered('Ninis has 12 dishes you can eat.'));

    render(<ChatClient />);
    await type('hi');

    expect(createConversation).toHaveBeenCalled();
    expect(await screen.findByText('Ninis has 12 dishes you can eat.')).toBeInTheDocument();
  });

  it('shows each tool the assistant runs', async () => {
    streamTurn.mockImplementation(async (_id, _text, onEvent) => {
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
          blocks: [{ type: 'tool_use', id: 't-1', name: 'get_menu', input: { restaurant: 'ninis' } }],
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
      streamTurn.mockImplementation(async (_id, _text, onEvent) => {
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

    it('asks before running it, and disables the composer meanwhile', async () => {
      render(<ChatClient />);
      await type('delete my review');

      expect(await screen.findByTestId('confirm-prompt')).toHaveTextContent('delete review');
      expect(streamConfirm).not.toHaveBeenCalled();
      expect(screen.getByLabelText('Message')).toBeDisabled();
    });

    // The fingerprint has to travel with the answer, or the server cannot
    // tell this approval apart from one meant for a different call.
    it('sends the answer the person gave, bound to the parked call', async () => {
      streamConfirm.mockResolvedValue(undefined);
      render(<ChatClient />);
      await type('delete my review');

      fireEvent.click(await screen.findByText('No'));

      await waitFor(() =>
        expect(streamConfirm).toHaveBeenCalledWith('c-1', false, 'fp-1', expect.anything()),
      );
    });

    // A declared sentence replaces the generic prompt and the JSON dump:
    // people should not have to read arguments to know what they are
    // agreeing to.
    it('renders the sentence the tool declared when there is one', async () => {
      const prompt = 'Stop avoiding nut-peanut? Dishes containing it will start showing as safe for you.';
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

  it('shows an error event without losing the conversation', async () => {
    streamTurn.mockImplementation(async (_id, _text, onEvent) => {
      onEvent({ type: 'error', message: 'This conversation has reached its spend limit.' });
    });

    render(<ChatClient />);
    await type('hi');

    expect(await screen.findByTestId('chat-error')).toHaveTextContent('spend limit');
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
    streamTurn.mockResolvedValue(undefined);

    render(<ChatClient />);
    const input = await screen.findByLabelText('Attach a menu photo or PDF');
    fireEvent.change(input, {
      target: { files: [new File(['x'], 'menu.jpg', { type: 'image/jpeg' })] },
    });

    expect(await screen.findByTestId('attachment-chips')).toHaveTextContent('menu.jpg');
    await type('read this');

    await waitFor(() =>
      expect(streamTurn).toHaveBeenCalledWith(
        'c-1',
        expect.stringContaining('attachment_id: signed-abc'),
        expect.anything(),
      ),
    );
  });
});
