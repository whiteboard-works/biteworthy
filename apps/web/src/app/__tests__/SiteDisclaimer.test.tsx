import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';

/**
 * The disclaimer is a legal commitment, so the interesting question is
 * not "does it render" but "where does it stop rendering, and does the
 * user still get it there". `/chat` is the one route that opts out of
 * the site-wide copy, and it opts out because it shows the same sentence
 * itself on an empty conversation — see the ChatClient spec for the
 * other half of that pair.
 */
const pathname = vi.fn(() => '/');
vi.mock('next/navigation', () => ({ usePathname: () => pathname() }));

const { SiteDisclaimer } = await import('../_SiteDisclaimer');

describe('SiteDisclaimer', () => {
  it('renders as page chrome on an ordinary page', () => {
    pathname.mockReturnValue('/restaurants/ninis');
    render(<SiteDisclaimer />);

    expect(screen.getByTestId('site-disclaimer')).toHaveTextContent(
      /planning aid, not a guarantee/,
    );
    expect(screen.getByRole('link', { name: 'Terms' })).toHaveAttribute('href', '/terms');
  });

  it('stands down on the chat, which shows it itself', () => {
    pathname.mockReturnValue('/chat');
    const { container } = render(<SiteDisclaimer />);

    expect(container).toBeEmptyDOMElement();
  });
});
