class IngestionItem < ApplicationRecord
  DECISIONS = %w[pending accepted rejected edited].freeze

  belongs_to :ingestion_run
  belongs_to :item, optional: true
  # Re-scan dedup: the existing Item this staged row was matched against
  # (Ingestion::ExistingItemMatcher). Distinct from :item, which is the
  # promotion result.
  belongs_to :matched_item, class_name: "Item", optional: true

  validates :decision, inclusion: { in: DECISIONS }

  DECISIONS.each do |d|
    define_method("#{d}?") { decision == d }
  end

  # "Worth a human look": text we could not match to the taxonomy, or nothing
  # resolved at all — either way the dietary filter would be wrong or empty
  # for this dish. In SQL rather than Ruby so a caller asking for these gets
  # them from the whole scan, not from whichever page a limit happened to cut.
  scope :needing_attention, -> {
    where(<<~SQL.squish)
      jsonb_array_length(COALESCE(unresolved_ingredients, '[]'::jsonb)) > 0
      OR jsonb_array_length(COALESCE(unresolved_tags, '[]'::jsonb)) > 0
      OR jsonb_array_length(COALESCE(ingredients_payload, '[]'::jsonb)) = 0
    SQL
  }

  # Materialize a staged ingestion item into a real Item +
  # ItemIngredient + ItemTag join rows. Called from the swipe-verify
  # UI (Phase 2.5) once a human has accepted (or edited then accepted)
  # the AI's suggestion.
  #
  # Phase 6.3 trust model: WHO verified decides the confidence level.
  # Admin (or legacy no-arg call sites — Avo is admin-gated) →
  # `confirmed`; a community scanner verifying their own run →
  # `suggested`. Either way `source: human` — a human signed off, the
  # question is whether strict-mode users should trust them yet.
  # Strict mode only shows fully-confirmed items, so community menus
  # are live for relaxed/balanced users and invisible to strict users
  # until an admin confirms (Phase 6.4's confirm-all action).
  #
  # Re-scan flow: when the resolve pass matched this staged row to an
  # existing Item (matched_item_id), accept APPLIES the scan as an
  # update — description/prices refreshed, new ingredients/tags appended
  # — instead of creating a duplicate. The exact changes are snapshotted
  # into applied_changes so undo! can restore them. If the matched Item
  # vanished (the FK nullifies on delete), accept falls back to create.
  #
  # Idempotent: re-calling on an already-promoted IngestionItem
  # returns the existing Item without creating duplicates.
  #
  # Returns the materialized Item; raises if the run has no
  # restaurant attached (which means we don't know where to put it).
  def promote!(decided_by: nil)
    return item if item.present?
    raise "IngestionRun ##{ingestion_run_id} has no restaurant" if promotion_run.restaurant_id.blank?

    confidence = decided_by.nil? || decided_by.is_admin? ? "confirmed" : "suggested"

    # requires_new: callers (ResolveItemsJob's batch promote) rescue a
    # failed promote and keep going inside their own transaction — a
    # savepoint makes this promote's partial writes roll back instead of
    # committing a live Item with missing allergen joins.
    transaction(requires_new: true) do
      # Re-read under lock: the gap-fill merge may have appended AI rows
      # since this record was loaded, and its row lock serializes us.
      lock!
      return item if item.present?

      target = locked_update_target
      target ? apply_update!(target, confidence) : create_item!(confidence)
    end
  end

  # Revert a verify decision back to :pending. Three shapes:
  # update-accept (item_id == matched_item_id — a fallback-create can
  # never look like this because the FK nullified the match when the
  # Item died) → restore the applied_changes snapshot; create-accept →
  # destroy the promoted Item (FK is RESTRICT, so unlink first); plain
  # edited/rejected → just reset. Never discriminate on
  # applied_changes.present? — a no-changes update-accept stores {}.
  def undo!
    transaction do
      lock!
      if item_id.present? && item_id == matched_item_id
        revert_update!
      else
        promoted = item
        update!(decision: "pending", item_id: nil, decided_at: nil, applied_changes: nil)
        promoted&.destroy
      end
    end
    self
  end

  private

  # `lock!` reloads the record, which clears its association cache — reading
  # `ingestion_run` after the lock would re-fetch the run and its restaurant
  # for every dish in a batch accept. The run can't change under us for the
  # length of one promote, so hold the one we already had.
  def promotion_run
    @promotion_run ||= ingestion_run
  end

  def create_item!(confidence)
    created = Item.create!(
      restaurant: promotion_run.restaurant,
      name:        name,
      description: description.presence,
      status:      "published",
      confidence:  confidence
    )

    insert_joins!(ItemIngredient, created, resolve_node_ids(Ingredient, ingredients_payload), confidence)
    insert_joins!(ItemTag,        created, resolve_node_ids(Tag,        tags_payload),        confidence)
    create_modifiers!(created)
    create_variants!(created)
    attach_dish_photo!(created)

    update!(item: created, decision: "accepted", decided_at: Time.current)
    created
  end

  # Merge the scan into the matched live Item. Semantics: description
  # overwritten only when the scan carries one and it differs (absence
  # of evidence never blanks data); variants replaced only when the
  # scanned price set is non-empty and differs; ingredients/tags are
  # append-only at accept-confidence — existing joins are never removed
  # or downgraded, so a human-confirmed association can't be undone by
  # a re-scan. Name, modifiers, and photo are deliberately untouched
  # (v1 non-goals — see docs/ingestion.md). Every change lands in the
  # applied_changes snapshot for undo!.
  def apply_update!(target, confidence)
    snapshot = {}

    apply_description!(target, snapshot)
    apply_variants!(target, snapshot)

    created_ingredient_ids =
      insert_joins!(ItemIngredient, target, resolve_node_ids(Ingredient, ingredients_payload), confidence)
    created_tag_ids =
      insert_joins!(ItemTag, target, resolve_node_ids(Tag, tags_payload), confidence)
    snapshot["created_item_ingredient_ids"] = created_ingredient_ids if created_ingredient_ids.any?
    snapshot["created_item_tag_ids"]        = created_tag_ids        if created_tag_ids.any?

    # A community accept that adds unconfirmed data to a fully-confirmed
    # Item must knock it back to suggested, or strict-mode users would
    # see an item whose newest (possibly allergen-bearing) association
    # nobody trusted yet. Never upgraded here — graduation stays with
    # Restaurant#confirm_community_associations!.
    if (created_ingredient_ids.any? || created_tag_ids.any?) &&
       confidence == "suggested" && target.confidence == "confirmed"
      snapshot["confidence"] = [target.confidence, "suggested"]
      target.update!(confidence: "suggested")
    end

    update!(item: target, decision: "accepted", decided_at: Time.current,
            applied_changes: snapshot)
    target
  end

  def locked_update_target
    return nil if matched_item_id.blank?

    Item.lock.find_by(id: matched_item_id, restaurant_id: promotion_run.restaurant_id)
  end

  def apply_description!(target, snapshot)
    scanned = description.to_s.strip
    return if scanned.blank? || scanned == target.description.to_s.strip

    snapshot["description"] = [target.description, description]
    target.update!(description: description)
  end

  def apply_variants!(target, snapshot)
    to = Ingestion::ItemUpdateDiff.normalize_prices(prices_payload)
    return if to.empty?

    from = Ingestion::ItemUpdateDiff.normalize_prices(
      target.item_variants.map { |v| { size: v.size, price_cents: v.price_cents } }
    )
    return if from == to

    snapshot["variants_replaced"] = target.item_variants.order(:position).map do |v|
      { "size" => v.size, "price_cents" => v.price_cents,
        "currency" => v.currency, "position" => v.position }
    end
    target.item_variants.destroy_all
    create_variants!(target)
  end

  # One lookup for the whole payload instead of one per row. Unknown slugs
  # are dropped on purpose — the extractor's noise must not fail a promotion
  # (Admin::ItemEditor does the opposite, because an admin who typed a bad
  # slug deserves to hear about it).
  def resolve_node_ids(model, payload)
    slugs = Ingestion::AssociationPayload.load_all(payload).filter_map { |row| row.slug.presence }.uniq
    return [] if slugs.empty?

    by_slug = model.where(slug: slugs).pluck(:slug, :id).to_h
    slugs.filter_map { |slug| by_slug[slug] }
  end

  # One INSERT per join table, then one recompute of the denormalized array.
  # Returns the ids actually created, which is what undo replays.
  #
  # insert_all skips validations, so `confidence` (the accept-confidence the
  # trust model decided) and `source: "human"` are written verbatim — the DB
  # CHECK constraints are the remaining guard. It also skips the callbacks
  # that keep items.ingredient_ids/tag_ids honest, hence the explicit resync.
  #
  # ON CONFLICT DO NOTHING (via unique_by) is what makes the append path
  # append-only: a slug already joined to this item is left exactly as it is,
  # confidence and all, and never comes back in the created list. That also
  # covers the concurrent-append race the old row-by-row rescue handled.
  def insert_joins!(model, target, node_ids, confidence)
    return [] if node_ids.empty?

    foreign_key = model.denormalized_foreign_key
    created = model.insert_all(
      node_ids.map do |node_id|
        { :item_id => target.id, foreign_key => node_id, :confidence => confidence, :source => "human" }
      end,
      unique_by: [:item_id, foreign_key],
      returning: %i[id]
    )
    model.resync_denormalized_ids([target.id])
    created.rows.flatten
  end

  # Restore what apply_update! changed, then release the link. Restore
  # is last-writer-wins over any manual edits made since the accept
  # (documented v1 caveat); matched_item_id survives so the card comes
  # back as an update card. Join destroys go row-by-row so the
  # after_destroy callbacks keep the denormalized id arrays honest — the
  # arrays are rebuilt once at the end of the block rather than per row.
  def revert_update!
    changes = applied_changes || {}
    target = Item.lock.find_by(id: item_id)

    if target
      if (change = changes["description"])
        target.update!(description: change[0])
      end
      if (change = changes["confidence"])
        target.update!(confidence: change[0])
      end
      if (rows = changes["variants_replaced"])
        target.item_variants.destroy_all
        rows.each do |row|
          ItemVariant.create!(
            item: target, size: row["size"], price_cents: row["price_cents"],
            currency: row["currency"] || "USD", position: row["position"] || 0
          )
        end
      end
      Item.defer_denormalization do
        ItemIngredient.where(id: changes["created_item_ingredient_ids"] || []).find_each(&:destroy)
        ItemTag.where(id: changes["created_item_tag_ids"] || []).find_each(&:destroy)
      end
    end

    update!(decision: "pending", item_id: nil, decided_at: nil, applied_changes: nil)
  end

  def create_variants!(target)
    # A size with no price is noise, not a variant — skip it.
    rows = Array(prices_payload).each_with_index.filter_map do |row, index|
      row = row.with_indifferent_access
      next if row[:price_cents].blank?

      { item_id: target.id, size: row[:size], price_cents: row[:price_cents], position: index }
    end
    ItemVariant.insert_all(rows) if rows.any?
  end

  def create_modifiers!(target)
    rows = Array(addons_payload).filter_map do |row|
      row = row.with_indifferent_access
      next if row[:name].blank?

      { item_id: target.id, name: row[:name], kind: "addition", price_cents: row[:price_cents] }
    end
    ItemModifier.insert_all(rows) if rows.any?
  end

  # Phase 4.11.3 — when Anthropic vision marked a per-dish photo on the
  # source page (image_bbox jsonb populated by 4.11.2), crop it out and
  # attach it to the new Item. Best-effort: a bad bbox or unreadable
  # source blob logs + skips so promotion still succeeds. The bbox
  # column stays null for items extracted by pre-4.11.2 cassettes; this
  # method is a no-op for them.
  def attach_dish_photo!(created_item)
    return if image_bbox.blank?
    source_blob = promotion_run.inputs.blobs.first
    return if source_blob.nil?

    cropped = Ingestion::DishPhotoCropper.call(source: source_blob, bbox: image_bbox)
    created_item.photo.attach(
      io:           cropped.io,
      filename:     "dish-#{created_item.id}.jpg",
      content_type: cropped.content_type
    )
  rescue StandardError => e
    Rails.logger.warn(
      "IngestionItem##{id} promote! photo attach skipped: #{e.class} #{e.message}"
    )
  end
end
