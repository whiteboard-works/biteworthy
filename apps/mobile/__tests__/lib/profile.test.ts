import { fetchChatNotes, ProfileError, saveChatNotes } from '../../lib/api/profile';

type FetchCall = Parameters<typeof fetch>;
type FetchMock = jest.Mock<Promise<Response>, FetchCall>;

function fakeFetch(status: number, body: unknown): FetchMock {
  return jest.fn(
    async (..._args: FetchCall) =>
      ({
        ok: status >= 200 && status < 300,
        status,
        json: async () => body,
      }) as unknown as Response,
  ) as FetchMock;
}

describe('fetchChatNotes (mobile)', () => {
  it('GETs /profile with the bearer token and returns the notes', async () => {
    const fetchImpl = fakeFetch(200, {
      chat_notes: 'Cooking for two kids.',
      strictness: 'balanced',
    });
    expect(await fetchChatNotes('jwt-123', { fetchImpl })).toBe('Cooking for two kids.');
    expect(String(fetchImpl.mock.calls[0]![0])).toContain('/api/v1/profile');
    const init = fetchImpl.mock.calls[0]![1] as { headers: Record<string, string> };
    expect(init.headers.Authorization).toBe('Bearer jwt-123');
  });

  it('throws ProfileError carrying the status', async () => {
    const fetchImpl = fakeFetch(401, {});
    await expect(fetchChatNotes('stale', { fetchImpl })).rejects.toMatchObject({ status: 401 });
  });
});

describe('saveChatNotes (mobile)', () => {
  // The profile PATCH replaces any array it receives wholesale. Sending
  // only the notes is what keeps a notes save from touching the avoid
  // lists that actually hide dishes.
  it('PATCHes only chat_notes and returns what the server stored', async () => {
    const fetchImpl = fakeFetch(200, { chat_notes: 'Mild only.' });
    expect(await saveChatNotes('  Mild only.  ', 'jwt-123', { fetchImpl })).toBe('Mild only.');
    const init = fetchImpl.mock.calls[0]![1] as { method: string; body: string };
    expect(init.method).toBe('PATCH');
    expect(JSON.parse(init.body)).toEqual({ chat_notes: '  Mild only.  ' });
  });

  it('throws ProfileError on failure', async () => {
    const fetchImpl = fakeFetch(422, { errors: { chat_notes: ['is too long'] } });
    await expect(saveChatNotes('x', 'jwt-123', { fetchImpl })).rejects.toBeInstanceOf(ProfileError);
  });
});
