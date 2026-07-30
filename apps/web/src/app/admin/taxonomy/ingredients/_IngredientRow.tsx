'use client';

import { useState } from 'react';
import {
  deleteIngredient,
  deleteRefusalCounts,
  updateIngredient,
  type AdminIngredient,
} from '../../../../lib/admin/taxonomy';
import { friendlyAdminError } from '../../../../lib/admin/shared';
import { ConfirmButton } from '../../_ConfirmButton';
import { StatusBadge } from '../../_StatusBadge';

/**
 * One taxonomy node. Only the mutable fields (name / aliases /
 * allergen) are editable — slug and path render read-only because the
 * server refuses changes to them (resolution keys). Delete goes
 * through the two-step confirm and, when refused, shows exactly what
 * still references the node.
 */
export function IngredientRow({
  ingredient,
  onUpdated,
  onDeleted,
}: {
  ingredient: AdminIngredient;
  onUpdated: (updated: AdminIngredient) => void;
  onDeleted: (id: string) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(ingredient.name);
  const [aliases, setAliases] = useState(ingredient.aliases.join(', '));
  const [allergen, setAllergen] = useState(ingredient.allergen);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      const updated = await updateIngredient(ingredient.id, {
        name,
        aliases: aliases.split(',').map((a) => a.trim()).filter(Boolean),
        allergen,
      });
      onUpdated(updated);
      setEditing(false);
    } catch (e) {
      setError(friendlyAdminError(e));
    } finally {
      setBusy(false);
    }
  };

  const destroy = async () => {
    setBusy(true);
    setError(null);
    try {
      await deleteIngredient(ingredient.id);
      onDeleted(ingredient.id);
    } catch (e) {
      const refs = deleteRefusalCounts(e);
      if (refs) {
        const held = Object.entries(refs)
          .filter(([, n]) => n > 0)
          .map(([k, n]) => `${n} ${k}`)
          .join(', ');
        setError(`Still referenced — ${held}. Remove those references first.`);
      } else {
        setError(friendlyAdminError(e));
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <li
      data-testid={`ingredient-${ingredient.slug}`}
      className="rounded-bw-lg border border-zinc-200 bg-white p-bw-3"
    >
      <div className="flex flex-wrap items-center justify-between gap-bw-2">
        <div className="min-w-0">
          <p className="font-semibold text-zinc-900">
            {ingredient.name}
            {ingredient.allergen && (
              <span className="ml-bw-2 align-middle">
                <StatusBadge tone="warn" label="allergen" />
              </span>
            )}
          </p>
          <p className="mt-bw-1 text-bw-xs text-zinc-500">
            {ingredient.path.split('.').join(' › ')} · {ingredient.slug} ·{' '}
            {ingredient.items_count} item{ingredient.items_count === 1 ? '' : 's'}
            {ingredient.aliases.length > 0 && <> · aka {ingredient.aliases.join(', ')}</>}
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-bw-2 text-bw-sm">
          <button
            type="button"
            onClick={() => setEditing((v) => !v)}
            data-testid={`ingredient-edit-${ingredient.slug}`}
            className="font-semibold text-zinc-600 hover:text-bite"
          >
            {editing ? 'Close' : 'Edit'}
          </button>
          <ConfirmButton
            label="Delete"
            busy={busy}
            onConfirm={() => void destroy()}
            testId={`ingredient-delete-${ingredient.slug}`}
          />
        </div>
      </div>

      {editing && (
        <div className="mt-bw-3 grid gap-bw-2 border-t border-zinc-100 pt-bw-3 text-bw-sm sm:grid-cols-2">
          <label className="flex flex-col gap-bw-1 text-zinc-600">
            Name
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              data-testid={`ingredient-name-${ingredient.slug}`}
              className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
            />
          </label>
          <label className="flex flex-col gap-bw-1 text-zinc-600">
            Aliases (comma-separated)
            <input
              value={aliases}
              onChange={(e) => setAliases(e.target.value)}
              data-testid={`ingredient-aliases-${ingredient.slug}`}
              className="rounded-bw-md border border-zinc-300 px-bw-2 py-bw-1"
            />
          </label>
          <label className="flex items-center gap-bw-2 text-zinc-600">
            <input
              type="checkbox"
              checked={allergen}
              onChange={(e) => setAllergen(e.target.checked)}
              data-testid={`ingredient-allergen-${ingredient.slug}`}
            />
            Allergen
          </label>
          <div className="flex items-center justify-end">
            <button
              type="button"
              onClick={() => void save()}
              disabled={busy}
              data-testid={`ingredient-save-${ingredient.slug}`}
              className="rounded-bw-md bg-bite px-bw-3 py-bw-1 font-semibold text-white disabled:opacity-50"
            >
              {busy ? 'Saving…' : 'Save'}
            </button>
          </div>
        </div>
      )}

      {error && (
        <p role="alert" className="mt-bw-2 text-bw-sm text-red-700">
          {error}
        </p>
      )}
    </li>
  );
}
