import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { FeatureRow } from '../_FeatureRow';

/**
 * Finding 4 in `docs/plans/ux-exploration-2026-08-15.md`: the homepage's
 * "📸 Scan the menu" tile was an inert card, so an anonymous visitor had
 * no path to the headline feature. The tile must link into /chat (which
 * login-bounces signed-out visitors); the other tiles stay plain cards.
 */
describe('FeatureRow', () => {
  it('links the scan tile to /chat with the beta hint', () => {
    render(<FeatureRow />);
    const link = screen.getByTestId('feature-scan-link');
    expect(link).toHaveAttribute('href', '/chat');
    expect(link).toHaveTextContent('Scan the menu');
    // Copy must read correctly in BOTH auth states — signed-in visitors
    // land straight in /chat, so no "sign in to …" phrasing.
    expect(link).toHaveTextContent(/free during the beta — start a scan/i);
  });

  it('keeps the other two tiles as plain cards, not links', () => {
    render(<FeatureRow />);
    expect(screen.getAllByRole('link')).toHaveLength(1);
    expect(screen.getByText('Pick your filter')).toBeInTheDocument();
    expect(screen.getByText('See only safe dishes')).toBeInTheDocument();
  });
});
