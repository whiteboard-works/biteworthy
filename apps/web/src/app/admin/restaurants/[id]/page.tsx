'use client';

import { use, useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import {
  fetchAdminRestaurant,
  fetchAdminRestaurantItems,
  updateAdminRestaurant,
  type AdminItemsResponse,
  type AdminRestaurantDetail,
} from '../../../../lib/admin/management';
import { confirmCommunity } from '../../../../lib/admin/runs';
import { AdminError, friendlyAdminError } from '../../../../lib/admin/shared';
import { ConfirmButton } from '../../_ConfirmButton';
import { StatusBadge } from '../../_StatusBadge';
import { AdminItemRowEditor } from './_AdminItemRowEditor';

/**
 * /admin/restaurants/[id] — the restaurant workbench: edit fields,
 * flip status (publish/unpublish/close), graduate community data to
 * strict-mode visibility, and manage every item regardless of status.
 */

const RESTAURANT_STATUSES = ['draft', 'published', 'closed'] as const;

export default function AdminRestaurantPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);

  const [restaurant, setRestaurant] = useState<AdminRestaurantDetail | null>(null);
  const [items, setItems] = useState<AdminItemsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [confirmResult, setConfirmResult] = useState<string | null>(null);
  const [form, setForm] = useState({ name: '', about: '', website: '', phone: '', status: 'draft' });

  const refresh = useCallback(async () => {
    setError(null);
    try {
      const detail = await fetchAdminRestaurant(id);
      setRestaurant(detail);
      setForm({
        name: detail.name,
        about: detail.about ?? '',
        website: detail.website ?? '',
        phone: detail.phone ?? '',
        status: detail.status,
      });
      setItems(await fetchAdminRestaurantItems(id, { limit: 200 }));
    } catch (e) {
      setError(friendlyAdminError(e));
    }
  }, [id]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  const save = async () => {
    setSaving(true);
    setError(null);
    try {
      const updated = await updateAdminRestaurant(id, {
        name: form.name,
        about: form.about,
        website: form.website,
        phone: form.phone,
        status: form.status,
      });
      setRestaurant((prev) => (prev ? { ...prev, ...updated } : prev));
    } catch (e) {
      const code = e instanceof AdminError ? e.code : null;
      setError(code ?? friendlyAdminError(e));
    } finally {
      setSaving(false);
    }
  };

  const onConfirmCommunity = async () => {
    setConfirming(true);
    setError(null);
    setConfirmResult(null);
    try {
      const res = await confirmCommunity(id);
      setConfirmResult(
        `Confirmed ${res.confirmed.items} item(s), ${res.confirmed.ingredients} ingredient link(s), ${res.confirmed.tags} tag link(s).`,
      );
      await refresh();
    } catch (e) {
      setError(friendlyAdminError(e));
    } finally {
      setConfirming(false);
    }
  };

  const suggestedCount = restaurant?.items_by_confidence?.suggested ?? 0;

  return (
    <main data-testid="admin-restaurant-detail" className="space-y-bw-6">
      <header>
        <Link href="/admin/restaurants" className="text-bw-xs font-semibold text-zinc-500 hover:text-bite">
          ← All restaurants
        </Link>
        <h1 className="mt-bw-1 flex items-center gap-bw-3 text-bw-2xl font-bold text-zinc-900">
          {restaurant?.name ?? 'Loading…'}
          {restaurant && (
            <StatusBadge
              label={restaurant.status}
              tone={restaurant.status === 'published' ? 'ok' : restaurant.status === 'closed' ? 'danger' : 'muted'}
            />
          )}
        </h1>
        {restaurant && (
          <p className="mt-bw-1 text-bw-xs text-zinc-500">
            {restaurant.slug} · {restaurant.city?.name ?? 'no city'}
          </p>
        )}
      </header>

      {error && (
        <div role="alert" data-testid="restaurant-error" className="rounded border border-red-300 bg-red-50 p-4 text-red-900">
          {error}
        </div>
      )}

      {restaurant && (
        <section
          data-testid="restaurant-form"
          className="grid gap-bw-2 rounded-bw-lg border border-zinc-200 bg-white p-bw-4 text-bw-sm sm:grid-cols-2"
        >
          <label className="flex flex-col gap-bw-1 text-zinc-600">
            Name
            <input
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              data-testid="restaurant-name"
              className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
            />
          </label>
          <label className="flex flex-col gap-bw-1 text-zinc-600">
            Status
            <select
              value={form.status}
              onChange={(e) => setForm({ ...form, status: e.target.value })}
              data-testid="restaurant-status"
              className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
            >
              {RESTAURANT_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-bw-1 text-zinc-600">
            Website
            <input
              value={form.website}
              onChange={(e) => setForm({ ...form, website: e.target.value })}
              data-testid="restaurant-website"
              className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
            />
          </label>
          <label className="flex flex-col gap-bw-1 text-zinc-600">
            Phone
            <input
              value={form.phone}
              onChange={(e) => setForm({ ...form, phone: e.target.value })}
              data-testid="restaurant-phone"
              className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
            />
          </label>
          <label className="flex flex-col gap-bw-1 text-zinc-600 sm:col-span-2">
            About
            <textarea
              value={form.about}
              onChange={(e) => setForm({ ...form, about: e.target.value })}
              data-testid="restaurant-about"
              rows={2}
              className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
            />
          </label>
          <div className="flex items-center justify-end sm:col-span-2">
            <button
              type="button"
              onClick={() => void save()}
              disabled={saving}
              data-testid="restaurant-save"
              className="rounded-bw-md bg-bite px-bw-3 py-bw-1 font-semibold text-white disabled:opacity-50"
            >
              {saving ? 'Saving…' : 'Save'}
            </button>
          </div>
        </section>
      )}

      {restaurant && (
        <section
          data-testid="restaurant-confirm-panel"
          className="flex flex-wrap items-center justify-between gap-bw-3 rounded-bw-lg border border-zinc-200 bg-white p-bw-4"
        >
          <div className="text-bw-sm text-zinc-700">
            <p className="font-semibold text-zinc-900">Strict-mode graduation</p>
            <p className="mt-bw-1 text-bw-xs text-zinc-500">
              {suggestedCount > 0
                ? `${suggestedCount} item(s) still carry suggested confidence.`
                : 'Everything here is confirmed.'}
            </p>
            {confirmResult && (
              <p role="status" data-testid="restaurant-confirm-result" className="mt-bw-1 text-ok">
                {confirmResult}
              </p>
            )}
          </div>
          <ConfirmButton
            label="Confirm community menu"
            busy={confirming}
            onConfirm={() => void onConfirmCommunity()}
            testId="restaurant-confirm-community"
          />
        </section>
      )}

      {items && (
        <section aria-labelledby="items-heading">
          <h2 id="items-heading" className="text-bw-sm font-semibold text-zinc-600">
            Items ({items.pagination.total})
          </h2>
          <ul className="mt-bw-2 space-y-bw-2">
            {items.items.map((item) => (
              <AdminItemRowEditor
                key={item.id}
                item={item}
                onUpdated={(updated) =>
                  setItems((prev) =>
                    prev
                      ? { ...prev, items: prev.items.map((i) => (i.id === updated.id ? updated : i)) }
                      : prev,
                  )
                }
              />
            ))}
          </ul>
        </section>
      )}
    </main>
  );
}
