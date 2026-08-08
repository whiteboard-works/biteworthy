'use client';

import { useRef, useState, type KeyboardEvent, type ReactElement } from 'react';
import { uploadAttachment, type Attachment } from '../../lib/chat';

interface ComposerProps {
  disabled: boolean;
  onSend: (text: string, attachments: Attachment[]) => void;
}

const ACCEPT = 'image/jpeg,image/png,image/heic,image/heif,image/webp,application/pdf';

export function Composer({ disabled, onSend }: ComposerProps): ReactElement {
  const [text, setText] = useState('');
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);

  const canSend = !disabled && !uploading && (text.trim().length > 0 || attachments.length > 0);

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
            // Prefers the rear camera on a phone, which is what a menu
            // photo needs; desktop browsers ignore it and show a picker.
            capture="environment"
            className="hidden"
            aria-label="Attach a menu photo or PDF"
            onChange={(e) => void attach(e.target.files)}
          />
        </label>

        <textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={onKeyDown}
          rows={1}
          disabled={disabled}
          aria-label="Message"
          placeholder="Ask what you can eat, or add a menu…"
          className="max-h-40 min-h-[42px] flex-1 resize-y rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base focus:border-bite focus:outline-none disabled:bg-zinc-50"
        />

        <button
          type="button"
          onClick={send}
          disabled={!canSend}
          className="rounded-bw-md bg-bite px-bw-4 py-bw-2 text-bw-base font-bold text-white hover:bg-bite-dark disabled:opacity-40"
        >
          Send
        </button>
      </div>
    </div>
  );
}
