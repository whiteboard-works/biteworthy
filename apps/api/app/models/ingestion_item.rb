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
    raise "IngestionRun ##{ingestion_run_id} has no restaurant" if ingestion_run.restaurant_id.blank?

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

  def create_item!(confidence)
    created = Item.create!(
      restaurant: ingestion_run.restaurant,
      name:        name,
      description: description.presence,
      status:      "published",
      confidence:  confidence
    )

    Array(ingredients_payload).each do |row|
      ingredient = resolve_ingredient(row)
      next if ingredient.nil?

      ItemIngredient.create!(
        item: created, ingredient: ingredient,
        confidence: confidence, source: "human"
      )
    end

    Array(tags_payload).each do |row|
      tag = resolve_tag(row)
      next if tag.nil?

      ItemTag.create!(
        item: created, tag: tag,
        confidence: confidence, source: "human"
      )
    end

    Array(addons_payload).each do |row|
      addon_name = row["name"] || row[:name]
      next if addon_name.blank?

      ItemModifier.create!(
        item: created, name: addon_name, kind: "addition",
        price_cents: row["price_cents"] || row[:price_cents]
      )
    end

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

    created_ingredient_ids = append_ingredients!(target, confidence)
    created_tag_ids        = append_tags!(target, confidence)
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

    Item.lock.find_by(id: matched_item_id, restaurant_id: ingestion_run.restaurant_id)
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

  def append_ingredients!(target, confidence)
    existing_ids = target.item_ingredients.pluck(:ingredient_id).to_set
    Array(ingredients_payload).filter_map do |row|
      ingredient = resolve_ingredient(row)
      next if ingredient.nil? || existing_ids.include?(ingredient.id)

      ItemIngredient.create!(
        item: target, ingredient: ingredient,
        confidence: confidence, source: "human"
      ).id
    end
  end

  def append_tags!(target, confidence)
    existing_ids = target.item_tags.pluck(:tag_id).to_set
    Array(tags_payload).filter_map do |row|
      tag = resolve_tag(row)
      next if tag.nil? || existing_ids.include?(tag.id)

      begin
        ItemTag.create!(item: target, tag: tag, confidence: confidence, source: "human").id
      rescue ActiveRecord::RecordNotUnique
        nil # (item_id, tag_id) unique index — someone else appended it first
      end
    end
  end

  # Restore what apply_update! changed, then release the link. Restore
  # is last-writer-wins over any manual edits made since the accept
  # (documented v1 caveat); matched_item_id survives so the card comes
  # back as an update card. Join destroys go row-by-row so the
  # after_destroy callbacks keep the denormalized id arrays honest.
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
      ItemIngredient.where(id: changes["created_item_ingredient_ids"] || []).find_each(&:destroy)
      ItemTag.where(id: changes["created_item_tag_ids"] || []).find_each(&:destroy)
    end

    update!(decision: "pending", item_id: nil, decided_at: nil, applied_changes: nil)
  end

  def create_variants!(target)
    # A size with no price is noise, not a variant — skip it.
    Array(prices_payload).each_with_index do |row, index|
      price_cents = row["price_cents"] || row[:price_cents]
      next if price_cents.blank?

      ItemVariant.create!(
        item: target, size: row["size"] || row[:size],
        price_cents: price_cents, position: index
      )
    end
  end

  def resolve_ingredient(row)
    slug = row["slug"] || row[:slug]
    return nil if slug.blank?

    Ingredient.find_by(slug: slug)
  end

  def resolve_tag(row)
    slug = row["slug"] || row[:slug]
    return nil if slug.blank?

    Tag.find_by(slug: slug)
  end

  # Phase 4.11.3 — when Anthropic vision marked a per-dish photo on the
  # source page (image_bbox jsonb populated by 4.11.2), crop it out and
  # attach it to the new Item. Best-effort: a bad bbox or unreadable
  # source blob logs + skips so promotion still succeeds. The bbox
  # column stays null for items extracted by pre-4.11.2 cassettes; this
  # method is a no-op for them.
  def attach_dish_photo!(created_item)
    return if image_bbox.blank?
    source_blob = ingestion_run.inputs.blobs.first
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
