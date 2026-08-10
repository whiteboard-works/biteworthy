'use client';

import { useEffect, useState } from 'react';

const KEY = 'bw_chat_show_tools';

/**
 * Whether tool calls are shown in the transcript.
 *
 * **Default on, deliberately.** Showing every tool call is the product's
 * honest-disclosure claim made visible — hiding what the assistant just
 * did to a menu would undercut the one thing this app promises. So this
 * is a per-person preference for a quieter read, not a new default.
 *
 * Read in an effect rather than during render: the server has no
 * `localStorage`, and reading it while rendering would hydrate a
 * different tree than the server sent.
 */
export function useToolVisibility(): [boolean, () => void] {
  const [show, setShow] = useState(true);

  useEffect(() => {
    try {
      setShow(window.localStorage.getItem(KEY) !== 'false');
    } catch {
      // Private mode, or storage disabled. The default stands.
    }
  }, []);

  const toggle = (): void => {
    setShow((current) => {
      const next = !current;
      try {
        window.localStorage.setItem(KEY, String(next));
      } catch {
        // Not being able to remember the choice is not a reason to
        // refuse it for this session.
      }
      return next;
    });
  };

  return [show, toggle];
}
