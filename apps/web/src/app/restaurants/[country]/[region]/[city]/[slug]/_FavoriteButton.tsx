'use client';

import { useState } from 'react';

/**
 * Save/unsave toggle shared by the restaurant and dish detail pages.
 * Optimistic: flips immediately, reverts on error. The caller supplies
 * `onToggle` (the lib fn bound to the right id) and the initial state
 * (SSR-seeded from the `favorited` flag on the show payload). Render it
 * only for signed-in users — the endpoint is authed.
 */
export default function FavoriteButton({
  initialFavorited,
  onToggle,
  savedLabel,
  unsavedLabel,
  testId,
}: {
  initialFavorited: boolean;
  onToggle: (next: boolean) => Promise<{ favorited: boolean }>;
  savedLabel: string;
  unsavedLabel: string;
  testId?: string;
}) {
  const [favorited, setFavorited] = useState(initialFavorited);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const toggle = async () => {
    const next = !favorited;
    setBusy(true);
    setError(null);
    setFavorited(next); // optimistic
    try {
      const res = await onToggle(next);
      setFavorited(res.favorited);
    } catch (e) {
      setFavorited(!next); // revert
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <span className="inline-flex flex-col items-start gap-bw-1">
      <button
        type="button"
        onClick={toggle}
        disabled={busy}
        aria-pressed={favorited}
        data-testid={testId}
        className={[
          'rounded-bw-pill border px-bw-4 py-bw-2 text-bw-sm font-semibold transition disabled:opacity-50',
          favorited
            ? 'border-bite bg-bite-light text-bite-dark'
            : 'border-zinc-300 bg-white text-zinc-700 hover:border-zinc-400',
        ].join(' ')}
      >
        {favorited ? `♥ ${savedLabel}` : `♡ ${unsavedLabel}`}
      </button>
      {error && <span className="text-bw-xs text-bite-dark">Could not save — try again.</span>}
    </span>
  );
}
