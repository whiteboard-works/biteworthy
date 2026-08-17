import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Anonymous visitors are bounced to /login on the server, before the
 * empty chat shell can flash (the client's own 401 handling remains the
 * fallback for sessions that expire mid-conversation). The check is
 * presence-only, so a stale-but-present JWT still renders the client.
 */

const mockRedirect = vi.hoisted(() => vi.fn());
vi.mock('next/navigation', () => ({ redirect: mockRedirect }));

const mockGetServerJwt = vi.hoisted(() => vi.fn());
vi.mock('../../../lib/server-auth', () => ({ getServerJwt: mockGetServerJwt }));

vi.mock('../_ChatClient', () => ({ ChatClient: () => null }));

import ChatPage from '../page';

beforeEach(() => {
  mockRedirect.mockReset();
  mockGetServerJwt.mockReset();
});

describe('ChatPage', () => {
  it('redirects anonymous visitors to login with a next back to /chat', async () => {
    mockGetServerJwt.mockResolvedValue(null);
    await ChatPage();
    expect(mockRedirect).toHaveBeenCalledWith('/login?next=%2Fchat');
  });

  it('renders the chat client when a session cookie is present', async () => {
    mockGetServerJwt.mockResolvedValue('some.jwt.value');
    await ChatPage();
    expect(mockRedirect).not.toHaveBeenCalled();
  });
});
