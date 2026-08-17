import { fetchMe, MeError, MeValidationError, updateMyHandle } from '../../lib/api/me';

const sampleUser = {
  id: 'u-1',
  email: 'sky@example.com',
  handle: 'diner_ab12cd34',
  display_name: 'Sky',
  is_admin: false,
  is_super_admin: false,
};

type FetchCall = Parameters<typeof fetch>;
type FetchMock = jest.Mock<Promise<Response>, FetchCall>;

function fakeFetch(status: number, body: unknown): FetchMock {
  return jest.fn(async (..._args: FetchCall) =>
    ({
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    }) as unknown as Response,
  ) as FetchMock;
}

describe('fetchMe (mobile)', () => {
  it('GETs /me with the bearer token and unwraps the user', async () => {
    const fetchImpl = fakeFetch(200, { user: sampleUser });
    const out = await fetchMe('jwt-123', { fetchImpl });

    expect(out).toEqual(sampleUser);
    expect(String(fetchImpl.mock.calls[0]![0])).toContain('/api/v1/me');
    const init = fetchImpl.mock.calls[0]![1] as { headers: Record<string, string> };
    expect(init.headers.Authorization).toBe('Bearer jwt-123');
  });

  it('throws MeError carrying the status on failure', async () => {
    const fetchImpl = fakeFetch(401, { error: 'unauthorized' });
    await expect(fetchMe('stale', { fetchImpl })).rejects.toMatchObject({
      name: 'MeError',
      status: 401,
    });
  });
});

describe('updateMyHandle (mobile)', () => {
  it('PATCHes the handle and returns the server payload (downcased there)', async () => {
    const fetchImpl = fakeFetch(200, { user: { ...sampleUser, handle: 'chosen_name' } });
    const out = await updateMyHandle('Chosen_Name', 'jwt-123', { fetchImpl });

    expect(out.handle).toBe('chosen_name');
    const init = fetchImpl.mock.calls[0]![1] as { method: string; body: string };
    expect(init.method).toBe('PATCH');
    expect(JSON.parse(init.body)).toEqual({ handle: 'Chosen_Name' });
  });

  // The 422 shape is per-field so the screen can say "already taken"
  // next to the input — a generic throw would lose which rule failed.
  it('rethrows a 422 as MeValidationError with the field messages', async () => {
    const fetchImpl = fakeFetch(422, { errors: { handle: ['has already been taken'] } });
    await expect(updateMyHandle('taken', 'jwt-123', { fetchImpl })).rejects.toMatchObject({
      name: 'MeValidationError',
      messages: ['has already been taken'],
    });
  });

  it('still raises MeValidationError when the 422 body is unreadable', async () => {
    const fetchImpl = fakeFetch(422, undefined);
    await expect(updateMyHandle('x', 'jwt-123', { fetchImpl })).rejects.toBeInstanceOf(
      MeValidationError,
    );
  });

  it('throws MeError on non-validation failures', async () => {
    const fetchImpl = fakeFetch(500, { error: 'boom' });
    await expect(updateMyHandle('fine_name', 'jwt-123', { fetchImpl })).rejects.toBeInstanceOf(
      MeError,
    );
  });
});
