'use client';

import { useState, type ChangeEvent, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import type { Route } from 'next';
import {
  ingestFromFile,
  ingestFromUrl,
  ingestFromText,
  friendlyIngestionError,
  IngestionRequestError,
} from '../../lib/ingestion';
import { NewRestaurantPicker } from './_NewRestaurantPicker';

/**
 * Phase 2.8 + 4.1 — web entrypoint for AI ingestion.
 * Phase 6.5 — community scan flow: any signed-in user picks or
 * creates the restaurant (with the Phase 6.2 dedup guard), uploads a
 * menu URL/PDF, and lands on /ingest/verify/<run> to swipe through
 * the extraction. Quota/budget errors (Phase 6.1) render as human
 * messages.
 */
export default function IngestPage() {
  const router = useRouter();

  const [restaurant, setRestaurant] = useState<{ id: string; name: string } | null>(null);
  const [manualId, setManualId] = useState('');
  const [sourceUrl, setSourceUrl] = useState('');
  const [sourceText, setSourceText] = useState('');
  const [file, setFile] = useState<File | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const restaurantId = restaurant?.id ?? manualId;

  const onPickFile = (e: ChangeEvent<HTMLInputElement>) => setFile(e.target.files?.[0] ?? null);

  const submit = async (mode: 'url' | 'file' | 'text') => {
    setError(null);
    if (!restaurantId) {
      setError('Pick or create a restaurant first.');
      return;
    }
    if (mode === 'url' && !sourceUrl) {
      setError('Paste a URL.');
      return;
    }
    if (mode === 'file' && !file) {
      setError('Drop a file.');
      return;
    }
    if (mode === 'text' && !sourceText.trim()) {
      setError('Paste the menu text.');
      return;
    }

    try {
      setSubmitting(true);
      const run =
        mode === 'url'
          ? await ingestFromUrl({ restaurantId, sourceUrl })
          : mode === 'file'
            ? await ingestFromFile({ restaurantId, file: file! })
            : await ingestFromText({ restaurantId, sourceText });
      router.push(`/ingest/verify/${run.id}` as Route);
    } catch (e) {
      if (e instanceof IngestionRequestError && e.status === 401) {
        router.replace(`/login?next=${encodeURIComponent('/ingest')}`);
        return;
      }
      setError(friendlyIngestionError(e));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <main className="mx-auto max-w-3xl space-y-8 p-6">
      <header>
        <p className="text-sm font-semibold uppercase tracking-widest text-orange-600">
          Scan a menu
        </p>
        <h1 className="mt-1 text-3xl font-bold">Add a restaurant’s menu</h1>
        <p className="mt-2 text-zinc-600">
          Pick the restaurant (or create it if it’s new), then give us the menu — a
          URL or a PDF. The AI extracts the items and you verify them before they go
          live.
        </p>
      </header>

      <section className="space-y-3 rounded-xl border border-zinc-200 p-4">
        <h2 className="text-lg font-semibold">1. Which restaurant?</h2>
        {restaurant ? (
          <div className="flex items-center justify-between rounded border border-green-300 bg-green-50 p-3">
            <p className="text-green-900">
              Scanning for <strong>{restaurant.name}</strong>
            </p>
            <button
              type="button"
              onClick={() => setRestaurant(null)}
              className="text-sm font-semibold text-green-900 underline"
            >
              Change
            </button>
          </div>
        ) : (
          <>
            <NewRestaurantPicker onPicked={setRestaurant} />
            <details className="text-sm text-zinc-500">
              <summary className="cursor-pointer">Already have a restaurant UUID?</summary>
              <input
                type="text"
                value={manualId}
                onChange={(e) => setManualId(e.target.value)}
                className="mt-2 w-full rounded border border-zinc-300 px-3 py-2 font-mono text-sm"
                placeholder="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
              />
            </details>
          </>
        )}
      </section>

      <section className="space-y-3 rounded-xl border border-zinc-200 p-4">
        <h2 className="text-lg font-semibold">2. From a URL</h2>
        <form
          onSubmit={(e: FormEvent) => {
            e.preventDefault();
            void submit('url');
          }}
          className="space-y-3"
        >
          <input
            type="url"
            value={sourceUrl}
            onChange={(e) => setSourceUrl(e.target.value)}
            placeholder="https://restaurant.example/menu"
            className="w-full rounded border border-zinc-300 px-3 py-2"
          />
          <button
            type="submit"
            disabled={submitting}
            className="rounded bg-orange-600 px-4 py-2 font-semibold text-white disabled:opacity-50"
          >
            {submitting ? 'Submitting…' : 'Scrape this URL'}
          </button>
        </form>
      </section>

      <section className="space-y-3 rounded-xl border border-zinc-200 p-4">
        <h2 className="text-lg font-semibold">Or drop a PDF / photo</h2>
        <div className="flex flex-wrap items-center gap-3">
          {/* capture="environment" opens the phone's rear camera directly.
              Kept separate from the picker below because `capture` would
              otherwise block PDF + existing-photo selection on mobile. */}
          <label className="inline-flex cursor-pointer items-center gap-2 rounded border border-orange-600 px-4 py-2 font-semibold text-orange-700 hover:bg-orange-50">
            📷 Take a photo
            <input
              type="file"
              accept="image/*"
              capture="environment"
              onChange={onPickFile}
              className="sr-only"
              data-testid="camera-input"
            />
          </label>
          <input
            type="file"
            accept="application/pdf,image/*"
            onChange={onPickFile}
            className="block text-sm"
            data-testid="file-input"
          />
        </div>
        {file && (
          <p className="text-sm text-zinc-700" data-testid="selected-file">
            Selected <span className="font-medium">{file.name}</span>
          </p>
        )}
        <button
          type="button"
          onClick={() => void submit('file')}
          disabled={submitting}
          className="rounded bg-orange-600 px-4 py-2 font-semibold text-white disabled:opacity-50"
        >
          {submitting ? 'Uploading…' : 'Upload file'}
        </button>
      </section>

      <section className="space-y-3 rounded-xl border border-zinc-200 p-4">
        <h2 className="text-lg font-semibold">Or paste the menu text</h2>
        <p className="text-sm text-zinc-600">
          Copy the menu from a website, email, or PDF and paste it here — handy when there’s no
          clean link or photo.
        </p>
        <textarea
          value={sourceText}
          onChange={(e) => setSourceText(e.target.value)}
          placeholder={'Appetizers\nHummus — chickpeas, tahini, olive oil … 8\n…'}
          rows={8}
          data-testid="paste-input"
          className="w-full rounded border border-zinc-300 px-3 py-2 font-mono text-sm"
        />
        <button
          type="button"
          onClick={() => void submit('text')}
          disabled={submitting}
          data-testid="paste-submit"
          className="rounded bg-orange-600 px-4 py-2 font-semibold text-white disabled:opacity-50"
        >
          {submitting ? 'Submitting…' : 'Import pasted text'}
        </button>
      </section>

      {error && (
        <div className="rounded border border-red-300 bg-red-50 p-4 text-red-900" role="alert">
          {error}
        </div>
      )}
    </main>
  );
}
