'use client';

import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type ClipboardEvent,
  type DragEvent,
  type KeyboardEvent,
  type ReactElement,
} from 'react';
import { uploadAttachment, type Attachment } from '../../lib/chat';

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
}

const ACCEPTED_TYPES = [
  'image/jpeg',
  'image/png',
  'image/heic',
  'image/heif',
  'image/webp',
  'application/pdf',
];
const ACCEPT = ACCEPTED_TYPES.join(',');

/** Chrome and Firefox hand over a dragged HEIC with no type at all. */
function accepted(file: File): boolean {
  if (ACCEPTED_TYPES.includes(file.type)) return true;
  return file.type === '' && /\.(heic|heif)$/i.test(file.name);
}

const carriesFiles = (types: readonly string[]) => types.includes('Files');

export function Composer({
  queueing,
  queued,
  onSend,
  onCancelQueued,
}: ComposerProps): ReactElement {
  const [text, setText] = useState('');
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [dragging, setDragging] = useState(false);
  const fileInput = useRef<HTMLInputElement>(null);
  const textarea = useRef<HTMLTextAreaElement>(null);

  // Grows with what is typed, up to max-h-40, then scrolls. A drag handle
  // was the only way to make it taller before, and iOS Safari has none.
  useLayoutEffect(() => {
    const el = textarea.current;
    if (!el) return;
    el.style.height = 'auto';
    // scrollHeight leaves out the border; border-box sizing counts it.
    el.style.height = `${el.scrollHeight + el.offsetHeight - el.clientHeight}px`;
  }, [text]);

  // A file dropped just past the composer would otherwise open in the
  // tab and take the conversation, and anything queued, with it.
  useEffect(() => {
    const swallow = (event: globalThis.DragEvent) => {
      if (event.dataTransfer && carriesFiles(Array.from(event.dataTransfer.types))) {
        event.preventDefault();
      }
    };
    window.addEventListener('dragover', swallow);
    window.addEventListener('drop', swallow);
    return () => {
      window.removeEventListener('dragover', swallow);
      window.removeEventListener('drop', swallow);
    };
  }, []);

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
    const usable = Array.from(files).filter(accepted);
    const skipped = Array.from(files).filter((file) => !accepted(file));
    setError(
      skipped.length > 0
        ? `Only photos and PDFs can be attached — skipped ${skipped.map((f) => f.name).join(', ')}.`
        : null,
    );
    if (usable.length === 0) return;
    setUploading(true);
    try {
      // One at a time: each upload shrinks a full-size photo first, and
      // several decoded at once can exceed Safari's canvas memory.
      const uploaded: Attachment[] = [];
      for (const file of usable) uploaded.push(await uploadAttachment(file));
      setAttachments((current) => [...current, ...uploaded]);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setUploading(false);
      if (fileInput.current) fileInput.current.value = '';
    }
  };

  const onDragOver = (event: DragEvent<HTMLDivElement>) => {
    if (!carriesFiles(event.dataTransfer.types)) return;
    event.preventDefault();
    setDragging(true);
  };

  const onDragLeave = (event: DragEvent<HTMLDivElement>) => {
    // Leaving the composer, not passing from it onto one of its children.
    if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setDragging(false);
  };

  const onDrop = (event: DragEvent<HTMLDivElement>) => {
    if (!carriesFiles(event.dataTransfer.types)) return;
    event.preventDefault();
    setDragging(false);
    void attach(event.dataTransfer.files);
  };

  // A spreadsheet or document copy carries the text plus a picture of it;
  // the text is what was meant, so only a files-only paste attaches.
  const onPaste = (event: ClipboardEvent<HTMLTextAreaElement>) => {
    const { files, types } = event.clipboardData;
    if (files.length === 0 || types.includes('text/plain')) return;
    event.preventDefault();
    void attach(files);
  };

  return (
    <div
      data-testid="composer"
      onDragEnter={onDragOver}
      onDragOver={onDragOver}
      onDragLeave={onDragLeave}
      onDrop={onDrop}
      className="relative border-t border-zinc-200 bg-white px-bw-4 py-bw-3"
    >
      {dragging ? (
        <div className="pointer-events-none absolute inset-1 z-10 flex items-center justify-center rounded-bw-md border-2 border-dashed border-bite bg-white/90 text-bw-base font-bold text-bite">
          Drop menu photos here
        </div>
      ) : null}
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

        <textarea
          ref={textarea}
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={onKeyDown}
          onPaste={onPaste}
          rows={1}
          aria-label="Message"
          placeholder={
            queueing
              ? 'Type the next one — it will send when this finishes…'
              : 'Ask what you can eat, or add a menu…'
          }
          className="max-h-40 min-h-[42px] flex-1 resize-none rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base focus:border-bite focus:outline-none"
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
