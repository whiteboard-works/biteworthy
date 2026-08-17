import type { ReactElement } from 'react';
import { CURRENT_VERSION } from '@biteworthy/version-history';

/**
 * The landing footer, extracted so the version link — the only
 * navigable entry point to /updates — can be pinned by a test instead
 * of living untested inside the page. The story page keeps its own
 * smaller footer (per-page footers are the deliberate convention here);
 * it carries the same version link inline.
 */
export function Footer(): ReactElement {
  return (
    <footer className="border-t border-zinc-200 bg-zinc-50 px-bw-6 py-bw-12">
      <div className="mx-auto flex max-w-5xl flex-col gap-bw-3 text-bw-sm text-zinc-500 md:flex-row md:items-center md:justify-between">
        <p>
          &copy; {new Date().getFullYear()} BiteWorthy &middot; Made in Durango, CO. &middot;{' '}
          <a href="/updates" data-testid="footer-version" className="hover:text-zinc-700">
            v{CURRENT_VERSION}
          </a>
        </p>
        <nav className="flex flex-wrap gap-bw-4">
          <a href="/restaurants" className="hover:text-zinc-700" data-testid="footer-restaurants">
            Restaurants
          </a>
          <a href="/story" className="hover:text-zinc-700" data-testid="footer-story">
            Our story
          </a>
          <a href="/privacy" className="hover:text-zinc-700" data-testid="footer-privacy">
            Privacy
          </a>
          <a href="/terms" className="hover:text-zinc-700" data-testid="footer-terms">
            Terms
          </a>
          <a href="/press" className="hover:text-zinc-700" data-testid="footer-press">
            Press
          </a>
          <a
            href="https://github.com/whiteboard-works/biteworthy"
            className="hover:text-zinc-700"
            data-testid="footer-github"
          >
            GitHub
          </a>
        </nav>
      </div>
    </footer>
  );
}
