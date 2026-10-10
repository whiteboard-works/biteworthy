import { describe, expect, it, vi } from 'vitest';
import {
  NotSignedInError,
  listConversations,
  answerConfirmation,
  renameConversation,
  sendMessage,
  watchTurn,
  uploadAttachment,
  compose,
  parseManifest,
  previewFor,
  type Attachment,
  type ChatEvent,
} from '../chat';
import { shrinkForUpload } from '../shrink-image';

vi.mock('../shrink-image', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../shrink-image')>();
  return { ...actual, shrinkForUpload: vi.fn(actual.shrinkForUpload) };
});

type FetchArgs = Parameters<typeof fetch>;
const MB = 1024 * 1024;

function jsonFetch(status: number, body: unknown) {
  return vi.fn(
    async (..._args: FetchArgs) =>
      ({
        ok: status >= 200 && status < 300,
        status,
        json: async () => body,
      }) as unknown as Response,
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
  return vi.fn(
    async (..._args: FetchArgs) => ({ ok: true, status: 200, body }) as unknown as Response,
  );
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

    await expect(sendMessage('c-1', 'x'.repeat(10))).rejects.toThrow('That message is too long.');
  });

  // The turn runs in a job, so asking for one returns as soon as it is
  // recorded rather than waiting out a model.
  it('asks for a turn and gets back the position to watch from', async () => {
    const fetchMock = jsonFetch(202, { queued: true, after: 7 });
    vi.stubGlobal('fetch', fetchMock);

    const queued = await sendMessage('c-1', 'hi');

    expect(queued.after).toBe(7);
    expect(fetchMock.mock.calls[0]?.[0]).toBe('/api/chat/conversations/c-1/messages');
  });

  // The fingerprint rides with the answer so the server can tell it apart
  // from an approval of some other call that happens to be parked now.
  it('sends the confirmation answer as a boolean, bound to the parked call', async () => {
    const fetchMock = jsonFetch(202, { queued: true, after: 3 });
    vi.stubGlobal('fetch', fetchMock);

    await answerConfirmation('c-1', false, 'fp-abc');

    const init = fetchMock.mock.calls[0]?.[1] as RequestInit;
    expect(fetchMock.mock.calls[0]?.[0]).toBe('/api/chat/conversations/c-1/confirm');
    expect(JSON.parse(init.body as string)).toEqual({ confirm: false, fingerprint: 'fp-abc' });
  });

  it('renames a conversation with a PATCH carrying only the title', async () => {
    const fetchMock = jsonFetch(200, { id: 'c-1', title: 'Lunch with Sam' });
    vi.stubGlobal('fetch', fetchMock);

    await expect(renameConversation('c-1', 'Lunch with Sam')).resolves.toMatchObject({
      title: 'Lunch with Sam',
    });
    const [path, init] = fetchMock.mock.calls[0]!;
    expect(path).toBe('/api/chat/conversations/c-1');
    expect(init?.method).toBe('PATCH');
    // Only the title: sending the mode alongside would stamp whatever this
    // tab thinks the mode is over a switch made on another device.
    expect(JSON.parse(init?.body as string)).toEqual({ title: 'Lunch with Sam' });
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
      await watchTurn('c-1', 0, (e) => seen.push(e));

      expect(seen.map((e) => e.type)).toEqual(['open', 'text_delta', 'text_delta', 'done']);
      expect(
        seen
          .filter((e) => e.type === 'text_delta')
          .map((e) => e.text)
          .join(''),
      ).toBe('Hello there.');
    });

    // Chunk boundaries follow the network, not the protocol: an event can
    // arrive split anywhere, and half a JSON payload must not be parsed.
    it('reassembles events split across chunks', async () => {
      const whole =
        frame({ type: 'text_delta', text: 'split' }) + frame({ type: 'done', text: 'split' });
      vi.stubGlobal('fetch', sseFetch([whole.slice(0, 12), whole.slice(12, 30), whole.slice(30)]));

      const seen: ChatEvent[] = [];
      await watchTurn('c-1', 0, (e) => seen.push(e));

      expect(seen).toEqual([
        { type: 'text_delta', text: 'split' },
        { type: 'done', text: 'split' },
      ]);
    });
  });

  // Events are stored, not just sent, so a reconnect asks for everything
  // after the last position it saw rather than starting the turn over.
  it('resumes the narration from the position it was given', async () => {
    const fetchMock = sseFetch([frame({ type: 'done', text: 'done' })]);
    vi.stubGlobal('fetch', fetchMock);

    await watchTurn('c-1', 12, () => {});

    expect(fetchMock.mock.calls[0]?.[0]).toBe('/api/chat/conversations/c-1/stream?after=12');
  });

  /** The ticket call succeeds; the upload itself answers `status` / `body`. */
  function uploadFetch(status: number, body: unknown) {
    return vi.fn(async (...[input]: FetchArgs) =>
      String(input).endsWith('/api/chat/attachments/ticket')
        ? ({
            ok: true,
            status: 201,
            json: async () => ({
              ticket: 'tkt-1',
              expires_at: '2026-10-10T00:10:00Z',
              max_bytes: 15 * MB,
            }),
          } as unknown as Response)
        : ({
            ok: status >= 200 && status < 300,
            status,
            json: async () => body,
          } as unknown as Response),
    );
  }

  // The bytes bypass this server's 4.5 MB body limit: a ticket from the
  // proxy, then the multipart straight to the API with it.
  it('mints a ticket, then uploads the attachment straight to the API', async () => {
    const fetchMock = uploadFetch(201, {
      id: 'signed-abc',
      filename: 'menu.jpg',
      content_type: 'image/jpeg',
      byte_size: 42,
    });
    vi.stubGlobal('fetch', fetchMock);

    const file = new File(['bytes'], 'menu.jpg', { type: 'image/jpeg' });
    await expect(uploadAttachment(file)).resolves.toMatchObject({ id: 'signed-abc' });

    expect(fetchMock.mock.calls[0]?.[0]).toBe('/api/chat/attachments/ticket');
    const [url, init] = fetchMock.mock.calls[1] as [string, RequestInit];
    expect(url).toMatch(/\/api\/v1\/attachments$/);
    expect(init.body).toBeInstanceOf(FormData);
    // The ticket rides as a header. Setting Content-Type by hand would
    // drop the multipart boundary, so it is the only header.
    expect(init.headers).toEqual({ 'X-Upload-Ticket': 'tkt-1' });
  });

  it('sends nothing when no ticket could be minted', async () => {
    const fetchMock = jsonFetch(401, { error: 'Not signed in' });
    vi.stubGlobal('fetch', fetchMock);

    await expect(
      uploadAttachment(new File(['x'], 'menu.jpg', { type: 'image/jpeg' })),
    ).rejects.toBeInstanceOf(NotSignedInError);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  // A full-size phone photo is a slow upload for nothing; what goes up
  // has to be the shrunk copy.
  it('uploads the shrunk copy of a photo, not the original', async () => {
    const fetchMock = uploadFetch(201, { id: 'signed-abc' });
    vi.stubGlobal('fetch', fetchMock);
    const original = new File([new Uint8Array(6 * 1024 * 1024)], 'IMG_1.HEIC', {
      type: 'image/heic',
    });
    const shrunk = new File(['small'], 'IMG_1.jpg', { type: 'image/jpeg' });
    vi.mocked(shrinkForUpload).mockResolvedValueOnce(shrunk);

    await uploadAttachment(original);

    const sent = ((fetchMock.mock.calls[1]?.[1] as RequestInit).body as FormData).get(
      'file',
    ) as File;
    expect(sent.name).toBe('IMG_1.jpg');
    expect(sent.size).toBe(shrunk.size);
  });

  // The sent bubble shows the photo — and an 80px tile should not cost a
  // full-size decode, so it is the shrunk copy too.
  it('keeps a preview of the shrunk copy once the upload is accepted', async () => {
    vi.stubGlobal('fetch', uploadFetch(201, { id: 'signed-preview' }));
    const shrunk = new File(['small'], 'IMG_2.jpg', { type: 'image/jpeg' });
    vi.mocked(shrinkForUpload).mockResolvedValueOnce(shrunk);
    const createObjectURL = vi.fn((_file: Blob) => 'blob:preview');
    // jsdom has no createObjectURL.
    vi.stubGlobal(
      'URL',
      class extends URL {
        static override createObjectURL = createObjectURL;
      },
    );

    await uploadAttachment(new File(['original'], 'IMG_2.HEIC', { type: 'image/heic' }));

    expect(createObjectURL).toHaveBeenCalledWith(shrunk);
    expect(previewFor('signed-preview')).toBe('blob:preview');
    vi.unstubAllGlobals();
  });

  it('keeps no preview for an upload the server refused', async () => {
    vi.stubGlobal('fetch', uploadFetch(422, { error: 'nope' }));
    const createObjectURL = vi.fn((_file: Blob) => 'blob:never');
    vi.stubGlobal(
      'URL',
      class extends URL {
        static override createObjectURL = createObjectURL;
      },
    );

    await expect(
      uploadAttachment(new File(['x'], 'menu.jpg', { type: 'image/jpeg' })),
    ).rejects.toThrow();
    expect(createObjectURL).not.toHaveBeenCalled();
    vi.unstubAllGlobals();
  });

  // Over the ceiling the ticket names, sending it only earns a 422 after
  // the whole upload. A PDF cannot be shrunk here, so the message says
  // what to do instead.
  it("refuses a file over the ticket's ceiling, with a message that says so, before sending it", async () => {
    const fetchMock = uploadFetch(201, { id: 'never' });
    vi.stubGlobal('fetch', fetchMock);
    const pdf = new File([new Uint8Array(16 * MB)], 'menu.pdf', { type: 'application/pdf' });

    await expect(uploadAttachment(pdf)).rejects.toThrow(/15 MB max/);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe('/api/chat/attachments/ticket');
  });

  // Minting the ticket just proved the session; a 401 on the upload is
  // the ticket (expired mid-upload), and a login redirect would throw
  // away a signed-in composer.
  it('reports a rejected ticket as an error, not as being signed out', async () => {
    vi.stubGlobal('fetch', uploadFetch(401, { error: 'That upload ticket is not valid.' }));

    const failure = uploadAttachment(new File(['x'], 'menu.jpg', { type: 'image/jpeg' }));
    await expect(failure).rejects.toThrow(/ticket is not valid/);
    await expect(failure).rejects.not.toBeInstanceOf(NotSignedInError);
  });

  it('explains a 413 from the server instead of showing the status code', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (...[input]: FetchArgs) =>
        String(input).endsWith('/ticket')
          ? ({
              ok: true,
              status: 201,
              json: async () => ({ ticket: 'tkt-1' }),
            } as unknown as Response)
          : ({
              ok: false,
              status: 413,
              json: async () => {
                throw new Error('html');
              },
            } as unknown as Response),
      ),
    );

    await expect(
      uploadAttachment(new File(['x'], 'menu.jpg', { type: 'image/jpeg' })),
    ).rejects.toThrow(/too large/);
  });

  // The reconnect event is transport bookkeeping — the transcript should
  // never see it, and the caller learns about it as a return value.
  it('swallows the reconnect event and returns the cursor', async () => {
    vi.stubGlobal(
      'fetch',
      sseFetch([
        frame({ type: 'text_delta', text: 'hi' }),
        frame({ type: 'reconnect', after: 12 }),
      ]),
    );

    const seen: ChatEvent[] = [];
    const resume = await watchTurn('c-1', 0, (e) => seen.push(e));

    expect(resume).toBe(12);
    expect(seen.map((e) => e.type)).toEqual(['text_delta']);
  });

  it('returns null when the turn genuinely ended', async () => {
    vi.stubGlobal('fetch', sseFetch([frame({ type: 'done', text: 'ok' })]));

    expect(await watchTurn('c-1', 0, () => {})).toBeNull();
  });
});

// The manifest is for the model. People see their own words plus the
// files, never a signed id — so whatever compose writes, parseManifest has
// to take back out exactly.
describe('parseManifest', () => {
  const photo = (id: string, filename: string): Attachment => ({
    id,
    filename,
    content_type: 'image/jpeg',
    byte_size: 10,
  });

  it('splits a composed message back into the words and the files', () => {
    const files = [photo('eyJ--abc', 'IMG_7978.jpg'), photo('eyJ--def', 'IMG_7977.jpg')];

    expect(parseManifest(compose('Can you add these?', files))).toEqual({
      text: 'Can you add these?',
      attachments: [
        { id: 'eyJ--abc', filename: 'IMG_7978.jpg' },
        { id: 'eyJ--def', filename: 'IMG_7977.jpg' },
      ],
    });
  });

  it('leaves a message with no manifest untouched', () => {
    expect(parseManifest('what can I eat\n\nat ninis')).toEqual({
      text: 'what can I eat\n\nat ninis',
      attachments: [],
    });
  });

  it('leaves no text behind when the photo is the whole message', () => {
    expect(parseManifest(compose('', [photo('id-1', 'menu.jpg')]))).toEqual({
      text: '',
      attachments: [{ id: 'id-1', filename: 'menu.jpg' }],
    });
  });

  it('keeps a filename that contains the separator or a bracket', () => {
    const odd = photo('id-2', 'lunch — page [2].jpg');

    expect(parseManifest(compose('', [odd])).attachments).toEqual([
      { id: 'id-2', filename: 'lunch — page [2].jpg' },
    ]);
  });
});
