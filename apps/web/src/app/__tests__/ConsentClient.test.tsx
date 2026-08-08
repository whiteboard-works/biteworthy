import { afterEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { ConsentClient } from '../oauth/consent/_ConsentClient';

const mockReplace = vi.fn();
const returnTo = 'http://api.test/oauth/authorize?client_id=abc&scope=profile%3Awrite';

vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace: mockReplace }),
  useSearchParams: () => new URLSearchParams({ return_to: returnTo }),
}));

const consent = {
  client: { name: 'Claude Desktop', uid: 'abc', confidential: false },
  scopes: [{ name: 'profile:write', description: 'Read and change your avoid lists' }],
  redirect_uri: 'https://claude.ai/cb',
  state: 'xyz',
  user: { id: 'u-1', email: 'me@example.com' },
};

function stubFetch(get: unknown, status = 200, post?: unknown) {
  const fetchMock = vi.fn(async (_url: string, init?: RequestInit) =>
    init?.method === 'POST'
      ? { ok: true, status: 200, json: async () => post }
      : { ok: status < 400, status, json: async () => get },
  );
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

/**
 * jsdom refuses a real navigation, so the assertion is on what the page
 * would navigate *to*. Only `location` is replaced — swapping the whole
 * `window` leaves testing-library without a container.
 */
function stubLocation() {
  const location = { href: '' };
  vi.stubGlobal('location', location);
  return location;
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});

describe('ConsentClient', () => {
  // A scope string is not consent. What renders has to be a sentence
  // someone can act on.
  it('shows who is asking and what each permission means', async () => {
    stubFetch(consent);
    render(<ConsentClient />);

    expect(await screen.findByText(/Claude Desktop/)).toBeInTheDocument();
    expect(screen.getByText('Read and change your avoid lists')).toBeInTheDocument();
  });

  // An app can call itself anything; where it sends you is registered and
  // cannot be faked, so the screen shows it.
  it('shows where approving will send the browser', async () => {
    stubFetch(consent);
    render(<ConsentClient />);

    expect(await screen.findByTestId('consent-redirect')).toHaveTextContent('https://claude.ai/cb');
  });

  // Signing in has to come back here, or the client is left waiting on an
  // authorization that never resumes.
  it('sends a signed-out visitor to log in and back again', async () => {
    stubFetch({}, 401);
    render(<ConsentClient />);

    await waitFor(() => expect(mockReplace).toHaveBeenCalled());
    expect(mockReplace.mock.calls[0]?.[0]).toContain(encodeURIComponent('/oauth/consent'));
  });

  it('follows the server-issued resume URL on approve', async () => {
    stubFetch(consent, 200, { redirect_to: 'http://api.test/oauth/authorize?handoff=t' });
    const location = stubLocation();
    render(<ConsentClient />);

    fireEvent.click(await screen.findByText('Approve'));

    await waitFor(() => expect(location.href).toBe('http://api.test/oauth/authorize?handoff=t'));
  });

  // A refusal goes back to the client so it stops waiting, rather than
  // leaving it hung on a window that just closed.
  it('returns access_denied to the client on cancel', async () => {
    stubFetch(consent);
    const location = stubLocation();
    render(<ConsentClient />);

    fireEvent.click(await screen.findByText('Cancel'));

    await waitFor(() => expect(location.href).toContain('error=access_denied'));
    expect(location.href).toContain('state=xyz');
  });

  it('says so when the request itself is not valid', async () => {
    stubFetch({ error: 'That redirect_uri is not registered for this client.' }, 422);
    render(<ConsentClient />);

    expect(await screen.findByTestId('consent-error')).toHaveTextContent('not registered');
  });
});
