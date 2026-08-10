'use client';

import { useState } from 'react';
import {
  itemEditErrorCopy,
  updateAdminItem,
  type AdminItemEdits,
  type AdminItemRow,
} from '../../../../lib/admin/management';
import { destroyAdminItem } from '../../../../lib/admin/deletes';
import { friendlyAdminError } from '../../../../lib/admin/shared';
import { HardDeleteButton } from '../../_HardDeleteButton';
import { StatusBadge, type BadgeTone } from '../../_StatusBadge';
import {
  ItemDeepEditPanel,
  type ItemDraft,
  draftFromItem,
  editsFromDraft,
} from './_ItemDeepEditPanel';

/**
 * One item in the restaurant workbench. The status select is the admin
 * unpublish lever — "removed" (hides the dish from every public menu
 * read) requires an explicit confirm; other transitions apply on
 * change. Edit opens the deep panel: name, description, prices,
 * modifiers, and the ingredient/tag chips that drive the allergen
 * filter.
 *
 * Confidence renders as a badge and is deliberately not editable — it
 * moves only through promote / confirm-community. Admin chip edits
 * land confirmed/human server-side, which is what makes them visible
 * to strict-mode users.
 */
/** Sourced from the generated contract so a server-side change breaks the build. */
type ItemStatus = NonNullable<AdminItemEdits['status']>;
const ITEM_STATUSES: readonly ItemStatus[] = ['draft', 'published', 'removed'];

const STATUS_TONES: Record<string, BadgeTone> = {
  draft: 'muted',
  published: 'ok',
  removed: 'danger',
};

const CONFIDENCE_TONES: Record<string, BadgeTone> = {
  confirmed: 'ok',
  suggested: 'warn',
  inferred: 'muted',
};

export function AdminItemRowEditor({
  item,
  sections,
  onUpdated,
  onDeleted,
}: {
  item: AdminItemRow;
  /** Sections of THIS restaurant, for the move-to-section select. */
  sections?: Array<{ id: string; name: string; menuName: string }>;
  onUpdated: (updated: AdminItemRow) => void;
  onDeleted: (id: string) => void;
}) {
  const [busy, setBusy] = useState(false);
  // Edit and the status select must go inert while a delete is in
  // flight — see HardDeleteButton's onBusyChange.
  const [deleting, setDeleting] = useState(false);
  const [pendingRemoval, setPendingRemoval] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [draft, setDraft] = useState<ItemDraft | null>(null);
  const [baseline, setBaseline] = useState<ItemDraft | null>(null);

  const save = async (edits: AdminItemEdits, thenClose = false) => {
    setBusy(true);
    setError(null);
    try {
      onUpdated(await updateAdminItem(item.id, edits));
      if (thenClose) {
        setDraft(null);
        setBaseline(null);
      }
    } catch (e) {
      setError(itemEditErrorCopy(e) ?? friendlyAdminError(e));
    } finally {
      setBusy(false);
    }
  };

  const setStatus = async (status: ItemStatus) => {
    setPendingRemoval(false);
    await save({ status });
  };

  const onSelect = (raw: string) => {
    const status = ITEM_STATUSES.find((s) => s === raw);
    if (!status || status === item.status) return;
    // Removal disappears the dish from every public menu — a stray
    // select change must not do that silently.
    if (status === 'removed') {
      setPendingRemoval(true);
      return;
    }
    void setStatus(status);
  };

  const openEditor = () => {
    const seed = draftFromItem(item);
    setBaseline(seed);
    setDraft(structuredClone(seed));
  };

  const closeEditor = () => {
    setDraft(null);
    setBaseline(null);
  };

  const price = item.variants?.[0]?.price_cents;

  return (
    <li
      data-testid={`admin-item-${item.id}`}
      className="rounded-bw-lg border border-zinc-200 bg-white p-bw-3"
    >
      <div className="flex flex-wrap items-center justify-between gap-bw-2">
        <div className="min-w-0">
          <p className="font-semibold text-zinc-900">
            {item.name}
            {price != null && (
              <span className="ml-bw-2 font-normal text-zinc-500">${(price / 100).toFixed(2)}</span>
            )}
          </p>
          <p className="mt-bw-1 text-bw-xs text-zinc-500">
            {(item.ingredients ?? []).map((i) => i.name).join(', ') || 'no ingredients'}
            {(item.tags ?? []).length > 0 && (
              <> · {(item.tags ?? []).map((t) => t.name).join(', ')}</>
            )}
            {item.description && <> · {item.description}</>}
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-bw-2 text-bw-sm">
          <StatusBadge
            label={item.confidence}
            tone={CONFIDENCE_TONES[item.confidence] ?? 'muted'}
          />
          <StatusBadge label={item.status} tone={STATUS_TONES[item.status] ?? 'muted'} />
          <button
            type="button"
            onClick={() => (draft ? closeEditor() : openEditor())}
            disabled={busy || deleting}
            data-testid={`admin-item-edit-${item.id}`}
            className="font-semibold text-zinc-600 hover:text-bite disabled:opacity-50"
          >
            {draft ? 'Close' : 'Edit'}
          </button>
          <select
            value={pendingRemoval ? 'removed' : item.status}
            onChange={(e) => onSelect(e.target.value)}
            disabled={busy || deleting}
            data-testid={`admin-item-status-${item.id}`}
            className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1 disabled:opacity-50"
          >
            {ITEM_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
          {/* `removed` above is the normal way off a menu — it keeps the
              reviews and saved-dish rows pointing at this item. Delete
              takes those with it. */}
          <HardDeleteButton
            onDelete={() => destroyAdminItem(item.id)}
            onDeleted={() => onDeleted(item.id)}
            onBusyChange={setDeleting}
            disabled={busy}
            testId={`admin-item-delete-${item.id}`}
          />
        </div>
      </div>

      {pendingRemoval && (
        <p className="mt-bw-2 flex items-center gap-bw-2 text-bw-sm text-zinc-700">
          Remove “{item.name}” from the public menu?
          <button
            type="button"
            onClick={() => void setStatus('removed')}
            data-testid={`admin-item-remove-confirm-${item.id}`}
            className="rounded-bw-md bg-danger px-bw-2 py-bw-1 font-bold text-white"
          >
            Remove
          </button>
          <button
            type="button"
            onClick={() => setPendingRemoval(false)}
            data-testid={`admin-item-remove-cancel-${item.id}`}
            className="font-semibold text-zinc-500 hover:text-zinc-800"
          >
            Cancel
          </button>
        </p>
      )}

      {draft && baseline && (
        <ItemDeepEditPanel
          itemId={item.id}
          draft={draft}
          sections={sections}
          busy={busy}
          onChange={setDraft}
          onCancel={closeEditor}
          onSave={() => void save(editsFromDraft(draft, baseline), true)}
        />
      )}

      {error && (
        <p role="alert" className="mt-bw-2 text-bw-sm text-red-700">
          {error}
        </p>
      )}
    </li>
  );
}
