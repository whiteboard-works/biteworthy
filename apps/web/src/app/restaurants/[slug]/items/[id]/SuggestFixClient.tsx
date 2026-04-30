'use client';

import { useState, type FormEvent } from 'react';
import {
  createSuggestion,
  SUGGESTION_KINDS,
  SuggestionError,
  type SuggestionKind,
} from '../../../../../lib/suggestions';

const KIND_LABELS: Record<SuggestionKind, string> = {
  add_ingredient:    'Add a missing ingredient',
  remove_ingredient: 'Remove a wrong ingredient',
  add_tag:           'Add a missing tag',
  remove_tag:        'Remove a wrong tag',
  rename:            'Fix a typo / rename',
};

const KIND_PAYLOAD_HINT: Record<SuggestionKind, string> = {
  add_ingredient:    'ingredient slug (e.g. herb-cilantro)',
  remove_ingredient: 'ingredient slug (e.g. herb-cilantro)',
  add_tag:           'tag slug (e.g. allergen-contains-dairy)',
  remove_tag:        'tag slug (e.g. allergen-contains-dairy)',
  rename:            'new item name',
};

/**
 * Phase 4.10 — "Suggest a fix" form on the item detail page. Anyone
 * can submit; the queue lands at /restaurants/<slug>/suggestions for
 * the claimed-restaurant owner to act on.
 */
export function SuggestFixClient({ itemId }: { itemId: string }) {
  const [open, setOpen] = useState(false);
  const [kind, setKind] = useState<SuggestionKind>('add_ingredient');
  const [value, setValue] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!value.trim()) {
      setError('Fill in the value.');
      return;
    }
    const payload = buildPayload(kind, value.trim());
    try {
      setSubmitting(true);
      await createSuggestion(itemId, { kind, payload });
      setDone(true);
      setValue('');
    } catch (err) {
      const status = err instanceof SuggestionError ? err.status : 0;
      setError(status === 422 ? 'Couldn’t accept that — double-check the value.' : (err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  if (done) {
    return (
      <p className="mt-bw-3 text-bw-sm text-zinc-500" data-testid="suggest-thanks">
        Thanks — your suggestion is in the queue.{' '}
        <button
          type="button"
          onClick={() => {
            setDone(false);
            setOpen(true);
          }}
          className="font-semibold text-bite hover:text-bite-dark"
        >
          Submit another
        </button>
      </p>
    );
  }

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        data-testid="open-suggest"
        className="mt-bw-3 text-bw-sm font-semibold text-zinc-500 hover:text-zinc-700"
      >
        Suggest a fix
      </button>
    );
  }

  return (
    <form onSubmit={submit} className="mt-bw-3 rounded-bw-md border border-zinc-200 p-bw-3" data-testid="suggest-form">
      <p className="text-bw-sm font-semibold text-zinc-700">Suggest a fix</p>
      <select
        value={kind}
        onChange={(e) => setKind(e.target.value as SuggestionKind)}
        aria-label="suggest-kind"
        className="mt-bw-2 w-full rounded-bw-md border border-zinc-300 px-bw-2 py-bw-2 text-bw-sm"
      >
        {SUGGESTION_KINDS.map((k) => (
          <option key={k} value={k}>{KIND_LABELS[k]}</option>
        ))}
      </select>
      <input
        type="text"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        placeholder={KIND_PAYLOAD_HINT[kind]}
        aria-label="suggest-value"
        required
        className="mt-bw-2 w-full rounded-bw-md border border-zinc-300 px-bw-2 py-bw-2 text-bw-sm"
      />
      {error && (
        <p className="mt-bw-2 rounded-bw-md bg-bite-light px-bw-2 py-bw-1 text-bw-xs text-bite-dark">
          {error}
        </p>
      )}
      <div className="mt-bw-2 flex items-center gap-bw-2 justify-end">
        <button
          type="button"
          onClick={() => setOpen(false)}
          className="text-bw-sm font-semibold text-zinc-500 hover:text-zinc-700"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={submitting}
          data-testid="submit-suggest"
          className={[
            'rounded-bw-md bg-zinc-700 px-bw-3 py-bw-2 text-bw-sm font-bold text-white',
            submitting ? 'opacity-60' : 'hover:bg-zinc-900',
          ].join(' ')}
        >
          {submitting ? 'Sending…' : 'Send suggestion'}
        </button>
      </div>
    </form>
  );
}

function buildPayload(kind: SuggestionKind, value: string): Record<string, unknown> {
  switch (kind) {
    case 'add_ingredient':
    case 'remove_ingredient':
      return { ingredient_slug: value };
    case 'add_tag':
    case 'remove_tag':
      return { tag_slug: value };
    case 'rename':
      return { name: value };
  }
}
