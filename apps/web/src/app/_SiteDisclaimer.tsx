'use client';

import type { ReactElement } from 'react';
import { usePathname } from 'next/navigation';

/**
 * The plain-language "at your own risk" line, without any chrome around
 * it. Exported so the chat can render the same sentence in its own
 * layout — the legal text has to live in exactly one place.
 */
export function DisclaimerNote({ className }: { className?: string }): ReactElement {
  // role="note", not a <footer>/contentinfo landmark — pages like the
  // marketing landing already have their own footer, and a second
  // contentinfo landmark is an accessibility smell.
  return (
    <div
      role="note"
      data-testid="site-disclaimer"
      className={`text-xs text-zinc-500 ${className ?? ''}`}
    >
      BiteWorthy is a planning aid, not a guarantee — dietary info can be wrong or out of date, so
      always confirm with the restaurant. Use at your own risk. See our{' '}
      <a href="/terms" className="underline hover:text-zinc-700">
        Terms
      </a>{' '}
      and{' '}
      <a href="/privacy" className="underline hover:text-zinc-700">
        Privacy Policy
      </a>
      .
    </div>
  );
}

/**
 * Slim, site-wide legal disclaimer shown as page chrome — everywhere
 * except the chat.
 *
 * The chat is the one route that sizes itself to the viewport
 * (`h-[calc(100dvh-4rem)]`), so a block appended after it does not share
 * the screen with the composer, it pushes past the bottom of it. On a
 * phone that is four lines of standing legal text under the send button
 * for the entire length of every conversation. `/chat` shows the same
 * sentence once, on a chat with nothing in it yet, where a person is
 * actually about to decide how much to trust the answers.
 */
export function SiteDisclaimer(): ReactElement | null {
  const pathname = usePathname();
  if (pathname === '/chat' || pathname.startsWith('/chat/')) return null;

  return <DisclaimerNote className="border-t border-zinc-200 px-6 py-4 text-center" />;
}
