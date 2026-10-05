import { describe, expect, it, vi, beforeEach } from 'vitest';
import { redirect } from 'next/navigation';
import LoginLayout from '../layout';
import * as serverAuth from '../../../lib/server-auth';

vi.mock('next/navigation', () => ({
  redirect: vi.fn(),
}));

describe('LoginLayout server-side redirect', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('redirects to / when user is signed in', async () => {
    // Mock getServerUserId to return a user ID (signed in)
    vi.spyOn(serverAuth, 'getServerUserId').mockResolvedValue('user-123');

    // Render the layout
    await LoginLayout({ children: <div>Login Form</div> });

    // Should redirect
    expect(redirect).toHaveBeenCalledWith('/');
  });

  it('renders children when user is signed out', async () => {
    // Mock getServerUserId to return null (signed out)
    vi.spyOn(serverAuth, 'getServerUserId').mockResolvedValue(null);

    // Render the layout
    const result = await LoginLayout({ children: <div>Login Form</div> });

    // Should NOT redirect
    expect(redirect).not.toHaveBeenCalled();
    
    // Should render children
    expect(result).toBeDefined();
  });

  it('renders children when cookie is malformed', async () => {
    // Mock getServerUserId to return null (malformed JWT)
    vi.spyOn(serverAuth, 'getServerUserId').mockResolvedValue(null);

    // Render the layout
    const result = await LoginLayout({ children: <div>Login Form</div> });

    // Should NOT redirect
    expect(redirect).not.toHaveBeenCalled();
    
    // Should render children
    expect(result).toBeDefined();
  });
});
