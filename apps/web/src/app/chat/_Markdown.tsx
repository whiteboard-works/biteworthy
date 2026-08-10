'use client';

import type { ReactElement, ReactNode } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

/**
 * Assistant text, rendered as markdown.
 *
 * The model writes lists, tables and emphasis whether or not anything
 * renders them, so `whitespace-pre-wrap` was showing people the asterisks.
 *
 * Two safety properties, both from *not* adding things:
 *
 *   * **No `rehype-raw`.** react-markdown ignores embedded HTML by
 *     default, and it stays that way. Two untrusted sources reach this
 *     component — the model, and restaurant text the model is quoting
 *     back (dish names and descriptions from strangers' photographs) —
 *     so a renderer that executed HTML would be an injection sink fed by
 *     a menu photo.
 *   * **Links are scheme-checked.** react-markdown sanitises `javascript:`
 *     already; the allowlist below is the belt to that braces, and it is
 *     cheap. Anything not http(s) renders as plain text rather than a
 *     link, and what does render carries `rel="noopener noreferrer"`.
 *
 * Styled with the app's own tokens rather than @tailwindcss/typography:
 * `prose` would be a second dependency and its scale is not this app's.
 */
const SAFE_SCHEMES = ['http:', 'https:'];

function isSafeHref(href: string | undefined): href is string {
  if (!href) return false;
  // Relative links are ours and always fine.
  if (href.startsWith('/') || href.startsWith('#')) return true;
  try {
    return SAFE_SCHEMES.includes(new URL(href).protocol);
  } catch {
    return false;
  }
}

export function Markdown({ text }: { text: string }): ReactElement {
  return (
    <div data-testid="markdown" className="text-bw-base leading-relaxed text-zinc-800">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          p: ({ children }) => <p className="mb-bw-2 last:mb-0">{children}</p>,
          ul: ({ children }) => (
            <ul className="mb-bw-2 list-disc space-y-bw-1 pl-bw-4 last:mb-0">{children}</ul>
          ),
          ol: ({ children }) => (
            <ol className="mb-bw-2 list-decimal space-y-bw-1 pl-bw-4 last:mb-0">{children}</ol>
          ),
          li: ({ children }) => <li className="pl-bw-1">{children}</li>,
          strong: ({ children }) => <strong className="font-semibold text-zinc-900">{children}</strong>,
          em: ({ children }) => <em className="italic">{children}</em>,
          h1: ({ children }) => <Heading>{children}</Heading>,
          h2: ({ children }) => <Heading>{children}</Heading>,
          h3: ({ children }) => <Heading>{children}</Heading>,
          h4: ({ children }) => <Heading>{children}</Heading>,
          code: ({ children }) => (
            <code className="rounded-bw-sm bg-zinc-100 px-bw-1 py-[1px] text-bw-sm">{children}</code>
          ),
          pre: ({ children }) => (
            <pre className="mb-bw-2 overflow-x-auto rounded-bw-md bg-zinc-100 p-bw-3 text-bw-sm last:mb-0">
              {children}
            </pre>
          ),
          blockquote: ({ children }) => (
            <blockquote className="mb-bw-2 border-l-2 border-zinc-200 pl-bw-3 text-zinc-600 last:mb-0">
              {children}
            </blockquote>
          ),
          hr: () => <hr className="my-bw-3 border-zinc-200" />,
          // GFM tables. Menus arrive as tables often enough to be worth
          // the styling, and they must scroll rather than widen the chat.
          table: ({ children }) => (
            <div className="mb-bw-2 overflow-x-auto last:mb-0">
              <table className="w-full border-collapse text-bw-sm">{children}</table>
            </div>
          ),
          th: ({ children }) => (
            <th className="border-b border-zinc-200 px-bw-2 py-bw-1 text-left font-semibold">
              {children}
            </th>
          ),
          td: ({ children }) => (
            <td className="border-b border-zinc-100 px-bw-2 py-bw-1 align-top">{children}</td>
          ),
          a: ({ href, children }) =>
            isSafeHref(href) ? (
              <a
                href={href}
                target="_blank"
                rel="noopener noreferrer"
                className="underline decoration-zinc-300 underline-offset-2 hover:decoration-zinc-500"
              >
                {children}
              </a>
            ) : (
              <span>{children}</span>
            ),
        }}
      >
        {text}
      </ReactMarkdown>
    </div>
  );
}

// One size for every level: these are headings inside a chat bubble, not
// a document outline, and six scales would look like a broken stylesheet.
function Heading({ children }: { children: ReactNode }): ReactElement {
  return <p className="mb-bw-1 mt-bw-2 font-semibold text-zinc-900 first:mt-0">{children}</p>;
}
