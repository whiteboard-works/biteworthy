'use client';

import { useState, type FormEvent } from 'react';
import {
  ingestFromFile,
  ingestFromUrl,
  type IngestionRunPayload,
} from '../../lib/ingestion';

/**
 * Phase 2.8 — admin entrypoint for AI ingestion via web.
 *
 * Two parallel ways to start a run:
 *   1. Paste a restaurant menu URL (HTML or PDF). Server-side
 *      `UrlFetcher` downloads it and attaches the body.
 *   2. Drop a PDF file. Same backend pipeline from the multipart side.
 *
 * Either way, the response carries the IngestionRun id; admin then
 * polls `/admin` (Avo) or, eventually, a follow-up web verify view
 * that mirrors the mobile swipe deck (out of scope for 2.8).
 */
export default function IngestPage() {
  const [restaurantId, setRestaurantId] = useState('');
  const [jwt, setJwt] = useState('');
  const [sourceUrl, setSourceUrl] = useState('');
  const [file, setFile] = useState<File | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [result, setResult] = useState<IngestionRunPayload | null>(null);
  const [error, setError] = useState<string | null>(null);

  const submit = async (mode: 'url' | 'file') => {
    setError(null);
    setResult(null);
    if (!restaurantId || !jwt) {
      setError('Restaurant id + JWT are required.');
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

    try {
      setSubmitting(true);
      const run =
        mode === 'url'
          ? await ingestFromUrl({ restaurantId, sourceUrl, jwt })
          : await ingestFromFile({ restaurantId, file: file!, jwt });
      setResult(run);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <main className="mx-auto max-w-3xl space-y-8 p-6">
      <header>
        <p className="text-sm font-semibold uppercase tracking-widest text-orange-600">
          Ingest a menu
        </p>
        <h1 className="mt-1 text-3xl font-bold">Web upload entrypoint</h1>
        <p className="mt-2 text-zinc-600">
          Paste a restaurant menu URL OR drop a PDF. Either way, the AI extracts the
          items and stages them for swipe-verify in <code>/admin</code>.
        </p>
      </header>

      <section className="space-y-3 rounded-xl border border-zinc-200 p-4">
        <label className="block">
          <span className="text-sm font-medium text-zinc-700">Restaurant UUID</span>
          <input
            type="text"
            value={restaurantId}
            onChange={(e) => setRestaurantId(e.target.value)}
            className="mt-1 w-full rounded border border-zinc-300 px-3 py-2 font-mono text-sm"
            placeholder="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
          />
        </label>
        <label className="block">
          <span className="text-sm font-medium text-zinc-700">JWT</span>
          <input
            type="password"
            value={jwt}
            onChange={(e) => setJwt(e.target.value)}
            className="mt-1 w-full rounded border border-zinc-300 px-3 py-2 font-mono text-sm"
            placeholder="paste the bearer token from /api/v1/auth/login"
          />
        </label>
      </section>

      <section className="space-y-3 rounded-xl border border-zinc-200 p-4">
        <h2 className="text-lg font-semibold">From a URL</h2>
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
        <h2 className="text-lg font-semibold">Or drop a PDF</h2>
        <input
          type="file"
          accept="application/pdf,image/*"
          onChange={(e) => setFile(e.target.files?.[0] ?? null)}
          className="block"
        />
        <button
          type="button"
          onClick={() => void submit('file')}
          disabled={submitting}
          className="rounded bg-orange-600 px-4 py-2 font-semibold text-white disabled:opacity-50"
        >
          {submitting ? 'Uploading…' : 'Upload file'}
        </button>
      </section>

      {error && (
        <div className="rounded border border-red-300 bg-red-50 p-4 text-red-900" role="alert">
          {error}
        </div>
      )}
      {result && (
        <div className="rounded border border-green-300 bg-green-50 p-4 text-green-900" role="status">
          <p>
            Run <code>{result.id}</code> → <strong>{result.status}</strong> (
            {result.input_kind})
          </p>
          <p className="mt-1 text-sm">
            Find it in /admin/resources/ingestion_runs.
          </p>
        </div>
      )}
    </main>
  );
}
