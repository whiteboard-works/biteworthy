import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';

import { Markdown } from '../_Markdown';

/**
 * Two untrusted sources reach this component: the model, and restaurant
 * text the model quotes back — dish names and descriptions transcribed
 * from strangers' photographs. So the safety assertions here are not
 * hypothetical, and they are about what the renderer refuses to do.
 */
describe('Markdown', () => {
  it('renders the structure the model actually writes', () => {
    render(<Markdown text={'Here are two:\n\n- **Tacos**\n- *Burritos*\n'} />);

    expect(screen.getByRole('list')).toBeInTheDocument();
    expect(screen.getAllByRole('listitem')).toHaveLength(2);
    expect(screen.getByText('Tacos').tagName).toBe('STRONG');
  });

  it('renders GFM tables, which is how menus arrive', () => {
    render(<Markdown text={'| Dish | Price |\n| --- | --- |\n| Taco | $4.50 |\n'} />);

    expect(screen.getByRole('table')).toBeInTheDocument();
    expect(screen.getByRole('cell', { name: 'Taco' })).toBeInTheDocument();
  });

  // No `rehype-raw`, and this is the spec that keeps it that way. A menu
  // photo containing HTML must not become HTML in someone's browser.
  it('does not execute embedded HTML', () => {
    const { container } = render(
      <Markdown text={'<img src=x onerror="alert(1)"> and <b>bold</b>'} />,
    );

    expect(container.querySelector('img')).toBeNull();
    expect(container.querySelector('b')).toBeNull();
  });

  it('links out safely', () => {
    render(<Markdown text="[menu](https://example.com/menu)" />);

    const link = screen.getByRole('link', { name: 'menu' });
    expect(link).toHaveAttribute('href', 'https://example.com/menu');
    expect(link).toHaveAttribute('rel', expect.stringContaining('noopener'));
    expect(link).toHaveAttribute('target', '_blank');
  });

  it('refuses a non-http scheme, keeping the words but dropping the link', () => {
    render(<Markdown text="[click me](javascript:alert(1))" />);

    expect(screen.queryByRole('link')).toBeNull();
    expect(screen.getByText('click me')).toBeInTheDocument();
  });

  // A protocol-relative URL starts with a slash and is *not* relative —
  // it is absolute and cross-origin, inheriting the page's scheme. The
  // "starts with / so it's ours" shortcut waved these straight through
  // without the allowlist ever seeing them.
  it.each(['//evil.tld/phish', '\\\\evil.tld/phish'])(
    'refuses the protocol-relative link %s',
    (href) => {
      render(<Markdown text={`[deal](${href})`} />);

      expect(screen.queryByRole('link')).toBeNull();
      expect(screen.getByText('deal')).toBeInTheDocument();
    },
  );

  // A single leading slash followed by a backslash never reaches the
  // browser as a protocol-relative URL — react-markdown percent-encodes
  // the backslash first, leaving an ordinary same-origin path. Pinned so
  // the guard above is not "hardened" against a case that is already safe.
  it('leaves a lone backslash as an encoded same-origin path', () => {
    render(<Markdown text={'[deal](/\\evil.tld/phish)'} />);

    expect(screen.getByRole('link', { name: 'deal' })).toHaveAttribute(
      'href',
      '/%5Cevil.tld/phish',
    );
  });

  it('still links a genuine same-origin path', () => {
    render(<Markdown text="[menu](/durango/vegan)" />);

    expect(screen.getByRole('link', { name: 'menu' })).toHaveAttribute('href', '/durango/vegan');
  });

  // Markdown collapses a single newline into a space, and a model
  // separating short lines with one `\n` — hours, an address, a dish per
  // line — is the common case. The old renderer preserved them.
  it('keeps single newlines as line breaks', () => {
    const { container } = render(<Markdown text={'Open now.\nCall ahead.'} />);

    const paragraph = container.querySelector('p');
    expect(paragraph?.className).toContain('whitespace-pre-wrap');
    expect(paragraph?.textContent).toBe('Open now.\nCall ahead.');
  });

  // A half-arrived list is rendered while it streams, so unterminated
  // markup has to degrade rather than throw.
  it('survives markup that is still arriving', () => {
    expect(() => render(<Markdown text={'| Dish | Pri'} />)).not.toThrow();
  });
});
