import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { CURRENT_VERSION, VERSION_HISTORY } from '@biteworthy/version-history';
import UpdatesPage, { metadata } from '../page';

/**
 * The /updates page renders the real version history. What's worth
 * locking: every entry appears, newest first, and the newest one is the
 * version the footer advertises — a page that silently dropped or
 * reordered releases would misrepresent what shipped.
 */

describe('UpdatesPage', () => {
  it('renders every release, newest first', () => {
    render(<UpdatesPage />);
    const headings = screen.getAllByRole('heading', { level: 2 });
    expect(headings.map((h) => h.textContent)).toEqual(
      VERSION_HISTORY.map((e) => `v${e.version}`),
    );
  });

  it('leads with the current version and its notes', () => {
    render(<UpdatesPage />);
    const first = screen.getByTestId(`release-${CURRENT_VERSION}`);
    expect(first).toHaveTextContent(`v${CURRENT_VERSION}`);
    expect(first).toHaveTextContent(VERSION_HISTORY[0]!.notes[0]!);
  });

  it('sets canonical metadata for /updates', () => {
    expect(metadata.title).toBe("What's new — BiteWorthy");
    expect(metadata.alternates?.canonical).toBe('/updates');
  });
});
