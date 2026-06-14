import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import TermsPage from '../page';

/**
 * Risk-reduction follow-up — the protective disclaimers only help if
 * they're conspicuous. These assert the prominent "use at your own
 * risk" summary box and that the AS-IS warranty + liability language is
 * present in its conspicuous (uppercase) form.
 */
describe('TermsPage — conspicuous disclaimers', () => {
  it('shows the top-of-page "use at your own risk" summary box', () => {
    render(<TermsPage />);
    const box = screen.getByTestId('summary-disclaimer');
    expect(box).toHaveTextContent(/use at your own risk/i);
    expect(box).toHaveTextContent(/confirm with the restaurant/i);
  });

  it('renders the AS-IS warranty + liability disclaimers conspicuously (uppercase)', () => {
    render(<TermsPage />);
    // The operative clauses are capitalized so they're "conspicuous".
    // ("AS IS"/"AS AVAILABLE" sit in their own <strong> nodes, so match
    // a phrase that lives in a single text node.)
    expect(screen.getByText(/WITHOUT WARRANTIES OF ANY KIND/)).toBeInTheDocument();
    expect(screen.getByText(/TO THE MAXIMUM EXTENT PERMITTED BY LAW/)).toBeInTheDocument();
  });
});
