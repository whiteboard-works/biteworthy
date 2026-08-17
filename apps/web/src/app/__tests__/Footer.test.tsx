import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { CURRENT_VERSION } from '@biteworthy/version-history';
import { Footer } from '../_Footer';

/**
 * The footer's version link is the only navigable way into /updates —
 * a refactor that drops it would leave the changelog reachable by URL
 * only, with no other CI signal.
 */

describe('Footer', () => {
  it('links the current version to /updates', () => {
    render(<Footer />);
    const version = screen.getByTestId('footer-version');
    expect(version).toHaveAttribute('href', '/updates');
    expect(version).toHaveTextContent(`v${CURRENT_VERSION}`);
  });

  it('keeps the site nav links', () => {
    render(<Footer />);
    for (const id of ['restaurants', 'story', 'privacy', 'terms', 'press', 'github']) {
      expect(screen.getByTestId(`footer-${id}`)).toBeInTheDocument();
    }
  });
});
