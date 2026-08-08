import {
  ChatError,
  answerConfirmation,
  compose,
  fetchEvents,
  sendMessage,
  stopTurn,
  type Attachment,
} from '../../lib/api/chat';

function jsonResponse(status: number, body: unknown) {
  return jest.fn(async () => ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  })) as unknown as typeof fetch;
}

describe('chat api', () => {
  // The turn runs in a job, so asking for one returns as soon as it is
  // recorded rather than waiting out a model.
  it('asks for a turn and gets back the cursor to watch from', async () => {
    const fetchImpl = jsonResponse(202, { queued: true, after: 7 });

    const queued = await sendMessage('jwt', 'c-1', 'hi', { fetchImpl });

    expect(queued.after).toBe(7);
    expect((fetchImpl as jest.Mock).mock.calls[0][0]).toContain('/api/v1/conversations/c-1/messages');
  });

  // Mobile polls where web streams: React Native's fetch exposes no
  // readable body, so SSE is not consumable without a polyfill. The rows
  // are the same either way.
  it('reads the narration after a cursor and says whether to ask again', async () => {
    const fetchImpl = jsonResponse(200, {
      events: [{ type: 'text_delta', text: 'Reading', position: 3 }],
      running: true,
    });

    const page = await fetchEvents('jwt', 'c-1', 2, { fetchImpl });

    expect(page.events[0]?.position).toBe(3);
    expect(page.running).toBe(true);
    expect((fetchImpl as jest.Mock).mock.calls[0][0]).toContain('after=2');
  });

  // The fingerprint binds the answer to the call that was drawn, so a
  // stale screen cannot approve a different one.
  it('sends the confirmation bound to the parked call', async () => {
    const fetchImpl = jsonResponse(202, { queued: true, after: 1 });

    await answerConfirmation('jwt', 'c-1', false, 'fp-abc', { fetchImpl });

    const init = (fetchImpl as jest.Mock).mock.calls[0][1] as RequestInit;
    expect(JSON.parse(init.body as string)).toEqual({ confirm: false, fingerprint: 'fp-abc' });
  });

  // A turn that already finished is not an error worth showing anyone.
  it('treats a 409 from stop as already finished', async () => {
    const fetchImpl = jsonResponse(409, { error: 'Nothing is running.' });

    await expect(stopTurn('jwt', 'c-1', { fetchImpl })).resolves.toBeUndefined();
  });

  it('surfaces the server message on a real failure', async () => {
    const fetchImpl = jsonResponse(422, { error: 'That message is too long.' });

    await expect(sendMessage('jwt', 'c-1', 'x', { fetchImpl })).rejects.toThrow(
      'That message is too long.',
    );
    await expect(sendMessage('jwt', 'c-1', 'x', { fetchImpl })).rejects.toBeInstanceOf(ChatError);
  });

  // Attachments travel as ids named in the message text, never as a side
  // channel — the transcript stays honest about what was sent, and the
  // model gets the id start_menu_scan needs.
  describe('compose', () => {
    const file: Attachment = {
      id: 'signed-abc',
      filename: 'menu.jpg',
      content_type: 'image/jpeg',
      byte_size: 10,
    };

    it('names each attachment and its id', () => {
      expect(compose('read this', [file])).toContain('attachment_id: signed-abc');
      expect(compose('read this', [file])).toContain('menu.jpg');
    });

    it('leaves a plain message alone', () => {
      expect(compose('hello', [])).toBe('hello');
    });

    it('works when the photo is the whole message', () => {
      expect(compose('', [file])).toBe('[Attached menu.jpg — attachment_id: signed-abc]');
    });
  });
});
