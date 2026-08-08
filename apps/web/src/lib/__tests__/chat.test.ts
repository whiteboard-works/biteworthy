import { describe, expect, it, vi } from 'vitest';
import {
  NotSignedInError,
  listConversations,
  streamConfirm,
  streamTurn,
  uploadAttachment,
  type ChatEvent,
} from '../chat';

type FetchArgs = Parameters<typeof fetch>;

function jsonFetch(status: number, body: unknown) {
  return vi.fn(
    async (..._args: FetchArgs) =>
      ({ ok: status >= 200 && status < 300, status, json: async () => body }) as unknown as Response,
  );
}

/** A body that yields the given chunks, so a split mid-event is testable. */
function sseFetch(chunks: string[]) {
  const encoder = new TextEncoder();
  let index = 0;
  const body = {
    getReader: () => ({
      read: async () =>
        index < chunks.length
          ? { done: false, value: encoder.encode(chunks[index++]) }
          : { done: true, value: undefined },
    }),
  };
  return vi.fn(async (..._args: FetchArgs) => ({ ok: true, status: 200, body }) as unknown as Response);
}

function frame(payload: unknown): string {
  return `data: ${JSON.stringify(payload)}\n\n`;
}

describe('chat client', () => {
  it('lists conversations', async () => {
    const fetchMock = jsonFetch(200, { conversations: [] });
    vi.stubGlobal('fetch', fetchMock);

    await expect(listConversations()).resolves.toEqual({ conversations: [] });
    expect(fetchMock.mock.calls[0]?.[0]).toBe('/api/chat/conversations');
  });

  // A stale session cookie has to send the user to sign in, not render an
  // empty chat that looks like they have no history.
  it('raises NotSignedInError on a 401', async () => {
    vi.stubGlobal('fetch', jsonFetch(401, { error: 'Not signed in' }));

    await expect(listConversations()).rejects.toBeInstanceOf(NotSignedInError);
  });

  it('surfaces the server error message', async () => {
    vi.stubGlobal('fetch', jsonFetch(422, { error: 'That message is too long.' }));

    await expect(
      streamTurn('c-1', 'x'.repeat(10), () => {}),
    ).rejects.toThrow('That message is too long.');
  });

  describe('streaming a turn', () => {
    it('reports each event in order', async () => {
      vi.stubGlobal(
        'fetch',
        sseFetch([
          frame({ type: 'open', conversation_id: 'c-1' }),
          frame({ type: 'text_delta', text: 'Hello ' }),
          frame({ type: 'text_delta', text: 'there.' }),
          frame({ type: 'done', text: 'Hello there.' }),
        ]),
      );

      const seen: ChatEvent[] = [];
      await streamTurn('c-1', 'hi', (e) => seen.push(e));

      expect(seen.map((e) => e.type)).toEqual(['open', 'text_delta', 'text_delta', 'done']);
      expect(seen.filter((e) => e.type === 'text_delta').map((e) => e.text).join('')).toBe(
        'Hello there.',
      );
    });

    // Chunk boundaries follow the network, not the protocol: an event can
    // arrive split anywhere, and half a JSON payload must not be parsed.
    it('reassembles events split across chunks', async () => {
      const whole = frame({ type: 'text_delta', text: 'split' }) + frame({ type: 'done', text: 'split' });
      vi.stubGlobal('fetch', sseFetch([whole.slice(0, 12), whole.slice(12, 30), whole.slice(30)]));

      const seen: ChatEvent[] = [];
      await streamTurn('c-1', 'hi', (e) => seen.push(e));

      expect(seen).toEqual([
        { type: 'text_delta', text: 'split' },
        { type: 'done', text: 'split' },
      ]);
    });

    // The fingerprint rides with the answer so the server can tell it apart
    // from an approval of some other call that happens to be parked now.
    it('sends the confirmation answer as a boolean, bound to the parked call', async () => {
      const fetchMock = sseFetch([frame({ type: 'done', text: 'Deleted.' })]);
      vi.stubGlobal('fetch', fetchMock);

      await streamConfirm('c-1', false, 'fp-abc', () => {});

      const init = fetchMock.mock.calls[0]?.[1] as RequestInit;
      expect(fetchMock.mock.calls[0]?.[0]).toBe('/api/chat/conversations/c-1/confirm');
      expect(JSON.parse(init.body as string)).toEqual({ confirm: false, fingerprint: 'fp-abc' });
    });
  });

  it('uploads an attachment as multipart and returns its id', async () => {
    const fetchMock = jsonFetch(201, {
      id: 'signed-abc',
      filename: 'menu.jpg',
      content_type: 'image/jpeg',
      byte_size: 42,
    });
    vi.stubGlobal('fetch', fetchMock);

    const file = new File(['bytes'], 'menu.jpg', { type: 'image/jpeg' });
    await expect(uploadAttachment(file)).resolves.toMatchObject({ id: 'signed-abc' });

    const init = fetchMock.mock.calls[0]?.[1] as RequestInit;
    expect(init.body).toBeInstanceOf(FormData);
    // Setting Content-Type by hand would drop the multipart boundary.
    expect(init.headers).toBeUndefined();
  });
});
