'use client';

import { useState, type FormEvent } from 'react';

/**
 * Legal remediation E10 — DMCA notice form. Posts to the Next proxy at
 * /api/dmca (→ Rails POST /api/v1/dmca_notices). Both §512(c)(3) sworn
 * statements are required checkboxes; the server rejects a notice that
 * omits either.
 */
export function DmcaForm() {
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [url, setUrl] = useState('');
  const [description, setDescription] = useState('');
  const [goodFaith, setGoodFaith] = useState(false);
  const [accuracySworn, setAccuracySworn] = useState(false);
  const [signature, setSignature] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  const ready =
    name && email && url && description && signature && goodFaith && accuracySworn && !submitting;

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      const res = await fetch('/api/dmca', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          complainant_name: name,
          complainant_email: email,
          infringing_url: url,
          work_description: description,
          good_faith: goodFaith,
          accuracy_sworn: accuracySworn,
          signature,
        }),
      });
      if (!res.ok) {
        const body = (await res.json().catch(() => ({}))) as { errors?: string[] };
        throw new Error(body.errors?.join(', ') || `Submission failed (${res.status})`);
      }
      setDone(true);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  if (done) {
    return (
      <div
        role="status"
        data-testid="dmca-done"
        className="mt-bw-8 rounded-bw-md border border-ok/40 bg-ok/10 p-bw-4 text-bw-sm text-zinc-800"
      >
        <strong>Notice received.</strong> Thank you — our team will review it and follow up at the
        email you provided.
      </div>
    );
  }

  const field = 'mt-1 w-full rounded-bw-md border border-zinc-300 px-bw-3 py-bw-2 text-bw-base';
  const labelText = 'text-bw-sm font-semibold text-zinc-700';

  return (
    <form onSubmit={onSubmit} className="mt-bw-8 flex flex-col gap-bw-4" data-testid="dmca-form">
      <h2 className="text-bw-xl font-bold text-zinc-900">File a notice</h2>

      <label>
        <span className={labelText}>Your name</span>
        <input value={name} onChange={(e) => setName(e.target.value)} required aria-label="dmca-name" className={field} />
      </label>
      <label>
        <span className={labelText}>Your email</span>
        <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required aria-label="dmca-email" className={field} />
      </label>
      <label>
        <span className={labelText}>URL of the infringing material</span>
        <input value={url} onChange={(e) => setUrl(e.target.value)} required aria-label="dmca-url" className={field} />
      </label>
      <label>
        <span className={labelText}>Describe the copyrighted work</span>
        <textarea value={description} onChange={(e) => setDescription(e.target.value)} required aria-label="dmca-description" rows={3} className={field} />
      </label>

      <label className="flex items-start gap-bw-2 text-bw-sm text-zinc-700">
        <input type="checkbox" checked={goodFaith} onChange={(e) => setGoodFaith(e.target.checked)} aria-label="dmca-good-faith" className="mt-bw-1 h-4 w-4 shrink-0" />
        <span>I have a good-faith belief that the use isn’t authorized by the owner, its agent, or the law.</span>
      </label>
      <label className="flex items-start gap-bw-2 text-bw-sm text-zinc-700">
        <input type="checkbox" checked={accuracySworn} onChange={(e) => setAccuracySworn(e.target.checked)} aria-label="dmca-accuracy" className="mt-bw-1 h-4 w-4 shrink-0" />
        <span>Under penalty of perjury, this notice is accurate and I am the owner or authorized to act for them.</span>
      </label>

      <label>
        <span className={labelText}>Signature (type your full name)</span>
        <input value={signature} onChange={(e) => setSignature(e.target.value)} required aria-label="dmca-signature" className={field} />
      </label>

      {error && (
        <p className="rounded-bw-md bg-bite-light px-bw-3 py-bw-2 text-bw-sm text-bite-dark">{error}</p>
      )}

      <button
        type="submit"
        disabled={!ready}
        data-testid="dmca-submit"
        className={[
          'rounded-bw-md bg-bite px-bw-4 py-bw-3 font-bold text-white',
          ready ? 'hover:bg-bite-dark' : 'opacity-60',
        ].join(' ')}
      >
        {submitting ? 'Submitting…' : 'Submit notice'}
      </button>
    </form>
  );
}
