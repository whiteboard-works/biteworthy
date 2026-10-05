import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, waitFor, act, fireEvent } from '@testing-library/react';
import { SiteHeader } from '../_SiteHeader';
import * as auth from '../../lib/auth';

// Mock Next.js router
const mockReplace = vi.fn();
const mockRefresh = vi.fn();
let currentPathname = '/';

vi.mock('next/navigation', () => ({
  useRouter: () => ({
    replace: mockReplace,
    refresh: mockRefresh,
  }),
  usePathname: () => currentPathname,
}));

describe('SiteHeader logout race condition', () => {
  let sessionResponses: Array<{ signedIn: boolean; delay?: number }>;
  let sessionCallIndex: number;

  beforeEach(() => {
    vi.clearAllMocks();
    sessionCallIndex = 0;
    sessionResponses = [];
    currentPathname = '/signup';

    // Mock fetch to control session responses
    global.fetch = vi.fn((url: string | URL) => {
      const urlString = typeof url === 'string' ? url : url.toString();
      
      if (urlString.includes('/api/auth/session')) {
        const response = sessionResponses[sessionCallIndex] || { signedIn: false };
        sessionCallIndex++;
        
        const delay = response.delay || 0;
        return new Promise((resolve) => {
          setTimeout(() => {
            resolve({
              ok: true,
              json: () => Promise.resolve({ signedIn: response.signedIn }),
            } as Response);
          }, delay);
        });
      }
      
      // Other endpoints
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ onboarded: true, admin: false }),
      } as Response);
    }) as typeof fetch;

    // Mock logout
    vi.spyOn(auth, 'logout').mockResolvedValue();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('prevents race: ignores session fetch that started before logout but completes after', async () => {
    // Setup: Initial mount returns signed in (slow response)
    // Then logout triggers a new fetch that returns signed out (fast)
    sessionResponses = [
      { signedIn: true, delay: 200 },  // Slow initial fetch
      { signedIn: false, delay: 10 },  // Fast post-logout fetch
    ];

    render(<SiteHeader />);

    // Wait for "Log out" button (proves initial signed-in state rendered)
    await waitFor(
      () => {
        expect(screen.getByTestId('nav-logout')).toBeInTheDocument();
      },
      { timeout: 300 }
    );

    // Click logout before the initial fetch completes
    await act(async () => {
      fireEvent.click(screen.getByTestId('nav-logout'));
    });

    // The fix: logoutGeneration counter increments, so the slow initial
    // fetch (which returns signedIn: true after 200ms) is ignored.
    // Without the fix, after 200ms the header would flip back to signed-in.
    
    // Wait for the slow fetch to complete
    await new Promise(resolve => setTimeout(resolve, 250));

    // Verify: header still shows signed-out state
    expect(screen.queryByTestId('nav-logout')).not.toBeInTheDocument();
    expect(screen.getByTestId('nav-signin')).toBeInTheDocument();
  });
});
