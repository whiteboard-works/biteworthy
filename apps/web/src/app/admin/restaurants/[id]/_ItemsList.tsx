'use client';

import { useState } from 'react';
import { updateAdminItem, type AdminItemRow } from '../../../../lib/admin/management';
import { friendlyAdminError } from '../../../../lib/admin/shared';
import { AdminItemRowEditor } from './_AdminItemRowEditor';
import { Pagination } from '../../_Pagination';

type Section = { id: string; name: string; menuName: string };

export function ItemsList({
  items,
  sections,
  pagination,
  onItemsChange,
  onItemDeleted,
  onOffsetChange,
}: {
  items: AdminItemRow[];
  sections: Section[];
  pagination: { total: number; limit: number; offset: number };
  onItemsChange: (items: AdminItemRow[]) => void;
  onItemDeleted: () => void;
  onOffsetChange: (offset: number) => void;
}) {
  const [draggedId, setDraggedId] = useState<string | null>(null);
  const [reorderError, setReorderError] = useState<string | null>(null);

  const handleDragStart = (e: React.DragEvent<HTMLLIElement>, id: string) => {
    setDraggedId(id);
    if (e.dataTransfer) {
      e.dataTransfer.effectAllowed = 'move';
    }
  };

  const handleDragOver = (e: React.DragEvent<HTMLLIElement>) => {
    e.preventDefault();
    if (e.dataTransfer) {
      e.dataTransfer.dropEffect = 'move';
    }
  };

  const handleDrop = async (e: React.DragEvent<HTMLLIElement>, targetId: string) => {
    e.preventDefault();
    setReorderError(null);

    if (!draggedId || draggedId === targetId) {
      setDraggedId(null);
      return;
    }

    const draggedItem = items.find((i) => i.id === draggedId);
    const targetItem = items.find((i) => i.id === targetId);

    if (!draggedItem || !targetItem) {
      setDraggedId(null);
      return;
    }

    // Only allow reordering within the same section
    if (draggedItem.menu_section_id !== targetItem.menu_section_id) {
      setReorderError('Items can only be reordered within the same section');
      setDraggedId(null);
      return;
    }

    const draggedIndex = items.indexOf(draggedItem);
    const targetIndex = items.indexOf(targetItem);

    const newItems = [...items];
    newItems.splice(draggedIndex, 1);
    newItems.splice(targetIndex, 0, draggedItem);

    // Update positions based on new order
    const sectionItems = newItems.filter((i) => i.menu_section_id === draggedItem.menu_section_id);
    const updates = sectionItems.map((item, index) => {
      const updated = { ...item, position: index };
      updateAdminItem(item.id, { position: index }).catch((err: unknown) => {
        setReorderError(friendlyAdminError(err));
      });
      return updated;
    });

    // Reconstruct full items list with updated positions
    const finalItems = newItems.map(
      (item) => updates.find((u) => u.id === item.id) || item
    );

    onItemsChange(finalItems);
    setDraggedId(null);
  };

  return (
    <section aria-labelledby="items-heading" className="space-y-bw-2">
      <h2 id="items-heading" className="text-bw-sm font-semibold text-zinc-600">
        Items ({pagination.total})
      </h2>
      {reorderError && (
        <div className="rounded border border-red-300 bg-red-50 p-2 text-bw-xs text-red-900">
          {reorderError}
        </div>
      )}
      <ul className="space-y-bw-2">
        {items.map((item) => (
          <li
            key={item.id}
            draggable
            onDragStart={(e) => handleDragStart(e, item.id)}
            onDragOver={handleDragOver}
            onDrop={(e) => void handleDrop(e, item.id)}
            className={`cursor-move transition-opacity ${
              draggedId === item.id ? 'opacity-50' : ''
            }`}
          >
            <AdminItemRowEditor
              item={item}
              sections={sections}
              onUpdated={(updated) =>
                onItemsChange(items.map((i) => (i.id === updated.id ? updated : i)))
              }
              onDeleted={() => onItemDeleted()}
            />
          </li>
        ))}
      </ul>
      <Pagination
        total={pagination.total}
        limit={pagination.limit}
        offset={pagination.offset}
        onOffset={onOffsetChange}
      />
    </section>
  );
}
