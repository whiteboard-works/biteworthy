'use client';

import { useEffect, useState } from 'react';
import {
  fetchDashboard,
  type AdminDashboardPayload,
  type DashboardBucket,
} from '../../lib/admin/metrics';
import { friendlyAdminError } from '../../lib/admin/shared';
import { StatusBadge, type BadgeTone } from './_StatusBadge';

/**
 * /admin ops dashboard — headline numbers, deliberately not charts:
 * one glance answers "is spend inside the ceiling, is cost-per-item
 * on target, is anything queued for moderation?". Data comes from
 * /api/admin/dashboard (Rails recomputes per request; nothing here is
 * cached). The layout has already confirmed the viewer is an admin —
 * failures here are transient (or a mid-session demotion, which the
 * friendly copy explains).
 */

const PERIOD_KEYS = ['today', 'last_7_days', 'last_30_days'] as const;

function dollars(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}

function spendBadge(spend: number, ceiling: number): { tone: BadgeTone; label: string } {
  if (ceiling <= 0) return { tone: 'muted', label: 'No ceiling set' };
  const pct = Math.round((spend / ceiling) * 100);
  if (spend >= ceiling) return { tone: 'danger', label: 'Ceiling reached — scans paused' };
  if (spend >= ceiling * 0.8) return { tone: 'warn', label: `${pct}% of daily ceiling` };
  return { tone: 'ok', label: `${pct}% of daily ceiling` };
}

const QUEUE_LABELS: Record<keyof AdminDashboardPayload['queues'], string> = {
  flagged_reviews: 'Flagged reviews',
  pending_suggestions: 'Pending suggestions',
  community_published_restaurants: 'Community-published restaurants',
  staged_runs: 'Staged ingestion runs',
};

export default function AdminHomePage() {
  const [data, setData] = useState<AdminDashboardPayload | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    fetchDashboard()
      .then((d) => {
        if (active) setData(d);
      })
      .catch((e: unknown) => {
        if (active) setError(friendlyAdminError(e));
      });
    return () => {
      active = false;
    };
  }, []);

  return (
    <main data-testid="admin-home">
      <h1 className="text-bw-2xl font-bold text-zinc-900">Ops dashboard</h1>

      {error && (
        <div
          role="alert"
          data-testid="dashboard-error"
          className="mt-bw-4 rounded border border-red-300 bg-red-50 p-4 text-red-900"
        >
          {error}
        </div>
      )}

      {!data && !error && (
        <p role="status" data-testid="dashboard-loading" className="mt-bw-4 text-bw-sm text-zinc-500">
          Loading metrics…
        </p>
      )}

      {data && (
        <div className="mt-bw-6 space-y-bw-6">
          <section
            data-testid="spend-card"
            aria-labelledby="spend-heading"
            className="rounded-bw-lg border border-zinc-200 bg-white p-bw-4"
          >
            <div className="flex items-center justify-between gap-bw-3">
              <h2 id="spend-heading" className="text-bw-sm font-semibold text-zinc-600">
                Community spend today
              </h2>
              <StatusBadge
                {...spendBadge(data.community.spend_today_cents, data.community.ceiling_cents)}
              />
            </div>
            <p className="mt-bw-2 text-bw-3xl font-bold text-zinc-900">
              {dollars(data.community.spend_today_cents)}
              <span className="ml-bw-2 text-bw-sm font-normal text-zinc-500">
                of {dollars(data.community.ceiling_cents)} ceiling ·{' '}
                {data.community.runs_today} community run
                {data.community.runs_today === 1 ? '' : 's'} today
              </span>
            </p>
          </section>

          <section aria-label="Ingestion cost and latency by period">
            <div className="grid gap-bw-4 sm:grid-cols-3">
              {PERIOD_KEYS.map((key) => (
                <PeriodTile
                  key={key}
                  periodKey={key}
                  bucket={data.periods[key]}
                  targetCentsPerItem={data.target_cents_per_item}
                />
              ))}
            </div>
          </section>

          <section aria-labelledby="queues-heading">
            <h2 id="queues-heading" className="text-bw-sm font-semibold text-zinc-600">
              Moderation queues
            </h2>
            <ul className="mt-bw-2 grid gap-bw-2 sm:grid-cols-2">
              {(Object.keys(QUEUE_LABELS) as Array<keyof typeof QUEUE_LABELS>).map((key) => (
                <li
                  key={key}
                  data-testid={`queue-${key}`}
                  className="flex items-center justify-between rounded-bw-md border border-zinc-200 bg-white px-bw-3 py-bw-2 text-bw-sm"
                >
                  <span className="text-zinc-700">{QUEUE_LABELS[key]}</span>
                  <span className="font-bold text-zinc-900">{data.queues[key]}</span>
                </li>
              ))}
            </ul>
          </section>
        </div>
      )}
    </main>
  );
}

function PeriodTile({
  periodKey,
  bucket,
  targetCentsPerItem,
}: {
  periodKey: string;
  bucket: DashboardBucket;
  targetCentsPerItem: number;
}) {
  const overTarget = bucket.item_count > 0 && bucket.cost_per_item_cents > targetCentsPerItem;

  return (
    <article
      data-testid={`period-${periodKey}`}
      className="rounded-bw-lg border border-zinc-200 bg-white p-bw-4"
    >
      <div className="flex items-center justify-between gap-bw-2">
        <h3 className="text-bw-sm font-semibold text-zinc-600">{bucket.label}</h3>
        {overTarget && <StatusBadge tone="warn" label="Over cost target" />}
      </div>
      <p className="mt-bw-2 text-bw-2xl font-bold text-zinc-900">
        {dollars(bucket.total_cost_cents)}
      </p>
      <dl className="mt-bw-2 space-y-1 text-bw-xs text-zinc-600">
        <div className="flex justify-between">
          <dt>Runs / items</dt>
          <dd className="font-semibold text-zinc-800">
            {bucket.run_count} / {bucket.item_count}
          </dd>
        </div>
        <div className="flex justify-between">
          <dt>Cost per item</dt>
          <dd className="font-semibold text-zinc-800">
            {bucket.cost_per_item_cents.toFixed(2)}¢
            <span className="font-normal text-zinc-500"> (target {targetCentsPerItem}¢)</span>
          </dd>
        </div>
        <div className="flex justify-between">
          <dt>Latency avg / p95</dt>
          <dd className="font-semibold text-zinc-800">
            {bucket.avg_latency_ms != null && bucket.p95_latency_ms != null
              ? `${bucket.avg_latency_ms} / ${bucket.p95_latency_ms} ms`
              : '—'}
          </dd>
        </div>
        <div className="flex justify-between">
          <dt>Cache hit rate</dt>
          <dd className="font-semibold text-zinc-800">{Math.round(bucket.cache_hit_rate * 100)}%</dd>
        </div>
      </dl>
    </article>
  );
}
