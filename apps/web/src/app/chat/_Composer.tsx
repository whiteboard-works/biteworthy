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

const ACCEPT = 'image/jpeg,image/png,image/heic,image/heif,image/webp,application/pdf';

/** Only an obvious mismatch is turned away here. The API sniffs the real
 *  type, and browsers often send none (a dragged HEIC) or an odd one
 *  (`image/jpg`) for a file it would take. */
const obviouslyUnusable = (file: File) =>
  file.type !== '' && !file.type.startsWith('image/') && file.type !== 'application/pdf';

const carriesFiles = (types: readonly string[]) => types.includes('Files');

export function Composer({
  queueing,
  queued,
  onSend,
  onCancelQueued,
}: ComposerProps): ReactElement {
  const [text, setText] = useState('');
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  // A count, not a flag: a paste can land while a drop is still uploading,
  // and Send must wait for both.
  const [uploads, setUploads] = useState(0);
  const uploading = uploads > 0;
  const [error, setError] = useState<string | null>(null);
  const [dragging, setDragging] = useState(false);
  // dragenter/dragleave fire for every child crossed; the target is up
  // while more have entered than left. Safari leaves relatedTarget null.
  const dragDepth = useRef(0);
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
        // Keep the no-drop cursor: outside the composer nothing is taken.
        event.dataTransfer.dropEffect = 'none';
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
    const picked = Array.from(files ?? []);
    // Cleared up front so picking the same file again still fires change.
    if (fileInput.current) fileInput.current.value = '';
    if (picked.length === 0) return;

    const problems: string[] = [];
    const skipped = picked.filter(obviouslyUnusable).map((file) => file.name);
    if (skipped.length > 0) {
      problems.push(`Only photos and PDFs can be attached — skipped ${skipped.join(', ')}.`);
    }
    setError(problems.join(' ') || null);

    const usable = picked.filter((file) => !obviouslyUnusable(file));
    if (usable.length === 0) return;
    setUploads((n) => n + 1);
    try {
      // One at a time: each upload shrinks a full-size photo first, and
      // several decoded at once can exceed Safari's canvas memory. Each
      // lands as it finishes, so one bad page does not cost the others.
      for (const file of usable) {
        try {
          const uploaded = await uploadAttachment(file);
          setAttachments((current) => [...current, uploaded]);
        } catch (e) {
          problems.push(`${file.name}: ${(e as Error).message}`);
          setError(problems.join(' '));
        }
      }
    } finally {
      setUploads((n) => n - 1);
    }
  };

  const onDragEnter = (event: DragEvent<HTMLDivElement>) => {
    if (!carriesFiles(event.dataTransfer.types)) return;
    event.preventDefault();
    dragDepth.current += 1;
    setDragging(true);
  };

  const onDragOver = (event: DragEvent<HTMLDivElement>) => {
    if (!carriesFiles(event.dataTransfer.types)) return;
    event.preventDefault();
    // The window handler marks drops elsewhere 'none'; this one is taken.
    event.dataTransfer.dropEffect = 'copy';
    event.stopPropagation();
  };

  const onDragLeave = (event: DragEvent<HTMLDivElement>) => {
    if (!carriesFiles(event.dataTransfer.types)) return;
    dragDepth.current = Math.max(0, dragDepth.current - 1);
    if (dragDepth.current === 0) setDragging(false);
  };

  const onDrop = (event: DragEvent<HTMLDivElement>) => {
    if (!carriesFiles(event.dataTransfer.types)) return;
    event.preventDefault();
    dragDepth.current = 0;
    setDragging(false);
    void attach(event.dataTransfer.files);
  };

  // A spreadsheet copy carries the cells' text plus a picture of them, and
  // the text is what was meant. A Finder copy carries the file plus its
  // name as text, and the file is what was meant.
  const onPaste = (event: ClipboardEvent<HTMLTextAreaElement>) => {
    const { files } = event.clipboardData;
    if (files.length === 0) return;
    const pastedText = event.clipboardData.getData('text/plain').trim();
    const names = Array.from(files).map((file) => file.name);
    if (pastedText && !pastedText.split(/\r?\n/).every((line) => names.includes(line.trim()))) {
      return;
    }
    event.preventDefault();
    void attach(files);
  };

  return (
    <div
      data-testid="composer"
      onDragEnter={onDragEnter}
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
