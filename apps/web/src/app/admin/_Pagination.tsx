'use client';

/**
 * Prev/next pager for admin lists. Offset-based to match the API's
 * limit/offset pagination; hidden entirely when one page suffices.
 */
export function Pagination({
  total,
  limit,
  offset,
  onOffset,
}: {
  total: number;
  limit: number;
  offset: number;
  onOffset: (nextOffset: number) => void;
}) {
  if (total <= limit) return null;

  const page = Math.floor(offset / limit) + 1;
  const pages = Math.max(1, Math.ceil(total / limit));

  return (
    <nav
      data-testid="admin-pagination"
      className="flex items-center justify-between text-bw-sm text-zinc-600"
      aria-label="Pagination"
    >
      <button
        type="button"
        onClick={() => onOffset(Math.max(0, offset - limit))}
        disabled={offset === 0}
        data-testid="admin-pagination-prev"
        className="font-semibold text-zinc-700 hover:text-bite disabled:opacity-40"
      >
        ← Previous
      </button>
      <span>
        Page {page} of {pages} · {total} total
      </span>
      <button
        type="button"
        onClick={() => onOffset(offset + limit)}
        disabled={offset + limit >= total}
        data-testid="admin-pagination-next"
        className="font-semibold text-zinc-700 hover:text-bite disabled:opacity-40"
      >
        Next →
      </button>
    </nav>
  );
}
