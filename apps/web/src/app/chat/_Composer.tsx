'use client';

import { useRef, useState, type KeyboardEvent, type ReactElement } from 'react';
import { uploadAttachment, type Attachment } from '../../lib/chat';
import type { LocationStatus } from './_useDeviceLocation';

/** A message typed while the assistant was busy. Held here until the
 *  turn it was typed during finishes. */
export interface QueuedMessage {
  id: string;
  /** The conversation it was typed into. `busy` is global, so a turn
   *  running in one chat must not deliver a message meant for another —
   *  A blank chat's messages carry that blank chat's own key until the
   *  chat is created, then its id. */
  conversationId: string | null;
  text: string;
  attachments: Attachment[];
}

interface ComposerProps {
  /** A turn is running or a confirmation is parked, so a send will be
   *  queued rather than delivered. Never disables the input — the whole
   *  point is that the next thought can be typed while this one lands. */
  queueing: boolean;
  queued: QueuedMessage[];
  onSend: (text: string, attachments: Attachment[]) => void;
  onCancelQueued: (id: string) => void;
  /** "Use my location". Omitted, the control is not shown. */
  location?: { status: LocationStatus; onToggle: () => void };
}

const LOCATION_NOTE: Partial<Record<LocationStatus, string>> = {
  locating: 'Finding your location…',
  denied: 'Location is blocked for this site. Allow it in your browser settings, or name a city.',
  unavailable: 'Could not get your location. Name a city instead.',
};

const ACCEPT = 'image/jpeg,image/png,image/heic,image/heif,image/webp,application/pdf';

export function Composer({
  queueing,
  queued,
  onSend,
  onCancelQueued,
  location,
}: ComposerProps): ReactElement {
  const [text, setText] = useState('');
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);

  // Deliberately not gated on whether a turn is running. The input used
  // to go dead for the length of a turn — which is a minute or more of a
  // menu scan — and a thought that arrives during one had nowhere to go
  // but the user's memory. It goes in the queue instead.
  const canSend = !uploading && (text.trim().length > 0 || attachments.length > 0);

  const send = () => {
    if (!canSend) return;
    onSend(text.trim(), attachments);
    setText('');
    setAttachments([]);
  };

  const onKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      send();
    }
  };

  const attach = async (files: FileList | null) => {
    if (!files || files.length === 0) return;
    setUploading(true);
    setError(null);
    try {
      const uploaded = await Promise.all(Array.from(files).map(uploadAttachment));
      setAttachments((current) => [...current, ...uploaded]);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setUploading(false);
      if (fileInput.current) fileInput.current.value = '';
    }
  };

  return (
    <div className="border-t border-zinc-200 bg-white px-bw-4 py-bw-3">
      {/* Cancelable, because "queued" and "sent" are different promises.
          A message that has not left yet is still the user's to take
          back, and the most common reason to want that is the assistant
          answering it on its own while they were typing. */}
      {queued.length > 0 ? (
        <ul className="mb-bw-2 space-y-bw-1" data-testid="queued-messages">
          {queued.map((message) => (
            <li
              key={message.id}
              className="flex items-start gap-bw-2 rounded-bw-md border border-dashed border-zinc-300 px-bw-3 py-bw-1 text-bw-sm text-zinc-500"
            >
              <span aria-hidden="true">⏳</span>
              <span className="min-w-0 flex-1 truncate">
                {message.text || `${message.attachments.length} attachment(s)`}
              </span>
              <button
                type="button"
                aria-label={`Cancel queued message: ${message.text || 'attachments'}`}
                onClick={() => onCancelQueued(message.id)}
                className="text-zinc-400 hover:text-zinc-700"
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      ) : null}

      {attachments.length > 0 ? (
        <ul className="mb-bw-2 flex flex-wrap gap-bw-2" data-testid="attachment-chips">
          {attachments.map((file) => (
            <li
              key={file.id}
              className="flex items-center gap-bw-2 rounded-bw-pill bg-zinc-100 px-bw-3 py-bw-1 text-bw-sm text-zinc-700"
            >
              {file.filename}
              <button
                type="button"
                aria-label={`Remove ${file.filename}`}
                onClick={() => setAttachments((c) => c.filter((f) => f.id !== file.id))}
                className="text-zinc-400 hover:text-zinc-700"
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      ) : null}

      {error ? (
        <p role="alert" className="mb-bw-2 text-bw-sm text-danger">
          {error}
        </p>
      ) : null}

      {location && LOCATION_NOTE[location.status] ? (
        <p role="status" className="mb-bw-2 text-bw-sm text-zinc-500">
          {LOCATION_NOTE[location.status]}
        </p>
      ) : null}

      <div className="flex items-end gap-bw-2">
        <label
          className="cursor-pointer rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-sm text-zinc-600 hover:bg-zinc-50"
          title="Attach a menu photo or PDF"
        >
          {uploading ? '…' : '+'}
          <input
            ref={fileInput}
            type="file"
            accept={ACCEPT}
            multiple
            className="hidden"
            aria-label="Attach a menu photo or PDF"
            onChange={(e) => void attach(e.target.files)}
          />
        </label>

        {location ? (
          <button
            type="button"
            onClick={location.onToggle}
            aria-pressed={location.status === 'on' || location.status === 'locating'}
            aria-label="Use my location"
            title={
              location.status === 'on'
                ? 'Sending your approximate location with each message. Tap to stop.'
                : 'Send your approximate location with each message, for “near me”.'
            }
            className={`rounded-bw-md border px-bw-3 py-bw-2 text-bw-sm ${
              location.status === 'on'
                ? 'border-bite bg-bite-light text-bite-dark'
                : 'border-zinc-300 text-zinc-600 hover:bg-zinc-50'
            }`}
          >
            <span aria-hidden="true">📍</span>
          </button>
        ) : null}

        <textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={onKeyDown}
          rows={1}
          aria-label="Message"
          placeholder={
            queueing
              ? 'Type the next one — it will send when this finishes…'
              : 'Ask what you can eat, or add a menu…'
          }
          className="max-h-40 min-h-[42px] flex-1 resize-y rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base focus:border-bite focus:outline-none"
        />

        <button
          type="button"
          onClick={send}
          disabled={!canSend}
          className="rounded-bw-md bg-bite px-bw-4 py-bw-2 text-bw-base font-bold text-white hover:bg-bite-dark disabled:opacity-40"
        >
          {queueing ? 'Queue' : 'Send'}
        </button>
      </div>
    </div>
  );
}
