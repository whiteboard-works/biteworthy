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

  # Payload sources that are guesses rather than something the menu said:
  # inferred from the dish name, or suggested by the model pass.
  INFERRED_SOURCES = %w[derived ai].freeze

  # "Worth a human look": text we could not match to the taxonomy, nothing
  # resolved at all, or only inferred ingredients (a pizza's wheat, a model
  # guess) and nothing the menu stated — in each case the dietary filter
  # would be wrong or empty for this dish. In SQL rather than Ruby so a
  # caller asking for these gets them from the whole scan, not from
  # whichever page a limit happened to cut. `needs_attention?` is the
  # same rule for one loaded row; keep the two in step.
  scope :needing_attention, -> {
    where(<<~SQL.squish, INFERRED_SOURCES)
      jsonb_array_length(COALESCE(unresolved_ingredients, '[]'::jsonb)) > 0
      OR jsonb_array_length(COALESCE(unresolved_tags, '[]'::jsonb)) > 0
      OR jsonb_array_length(COALESCE(ingredients_payload, '[]'::jsonb)) = 0
      OR NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(COALESCE(ingredients_payload, '[]'::jsonb)) AS row
        WHERE COALESCE(row->>'source', '') NOT IN (?)
      )
    SQL
  }

  def needs_attention?
    rows = ::Ingestion::AssociationPayload.load_all(ingredients_payload)
    Array(unresolved_ingredients).any? || Array(unresolved_tags).any? || rows.empty? ||
      rows.all? { |row| INFERRED_SOURCES.include?(row.source) }
  end

  # Materialize a staged ingestion item into a real Item +
  # ItemIngredient + ItemTag join rows. Called from the swipe-verify
  # UI (Phase 2.5) once a human has accepted (or edited then accepted)
  # the AI's suggestion.
  #
  # Confidence model: each ingredient/tag row's (source, confidence) is
  # mapped from the payload under the locked confidence rules (see
  # Ingestion::ConfidenceMapper). The dish's own confidence is the
  # weakest of its INGREDIENTS (not tags): zero ingredients → suggested;
  # otherwise min(ingredient confidences). Admin acceptors can produce
  # confirmed joins; community acceptors cap at suggested. Strict mode
  # only shows fully-confirmed items, so community menus are live for
  # relaxed/balanced users and invisible to strict users until an admin
  # confirms (Phase 6.4's confirm-all action).
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

    # requires_new: callers (ResolveItemsJob's batch promote) rescue a
    # failed promote and keep going inside their own transaction — a
    # savepoint makes this promote's partial writes roll back instead of
    # committing a live Item with missing allergen joins.
    transaction(requires_new: true) do
      # Re-read under lock: the gap-fill merge may have appended AI rows
      # since this record was loaded, and its row lock serializes us.
      lock!
      return item if item.present?
      # A reject may have landed between this record's load and the lock;
      # publishing it now would put a dish the person turned down on the
      # live menu while the audit row says rejected.
      raise "Staged dish was rejected; undo it before accepting" if rejected?

      target = locked_update_target
      target ? apply_update!(target, decided_by: decided_by) : create_item!(decided_by: decided_by)
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

  def create_item!(decided_by:)
    # Compute dish confidence from ingredients only (not tags).
    # Zero ingredients → suggested. Otherwise → weakest ingredient confidence.
    ingredient_rows = map_joins_with_confidence(Ingredient, ingredients_payload, decided_by: decided_by)
    dish_confidence = Ingestion::ConfidenceMapper.dish_confidence_from_ingredients(ingredient_rows)

    created = Item.create!(
      restaurant:     promotion_run.restaurant,
      menu_section:   find_or_create_section,
      name:           name,
      description:    description.presence,
      status:         "published",
      confidence:     dish_confidence
    )

    insert_joins_with_confidence!(ItemIngredient, created, ingredient_rows)
    tag_rows = map_joins_with_confidence(Tag, tags_payload, decided_by: decided_by)
    insert_joins_with_confidence!(ItemTag, created, tag_rows)
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
  # append-only — existing joins are never removed or downgraded, so a
  # human-confirmed association can't be undone by a re-scan. Name,
  # modifiers, and photo are deliberately untouched (v1 non-goals — see
  # docs/ingestion.md). Section is set only when missing. Every change
  # lands in the applied_changes snapshot for undo!.
  def apply_update!(target, decided_by:)
    snapshot = {}

    apply_description!(target, snapshot)
    apply_section!(target, snapshot)
    apply_variants!(target, snapshot)

    ingredient_rows = map_joins_with_confidence(Ingredient, ingredients_payload, decided_by: decided_by)
    created_ingredient_ids = insert_joins_with_confidence!(ItemIngredient, target, ingredient_rows)

    tag_rows = map_joins_with_confidence(Tag, tags_payload, decided_by: decided_by)
    created_tag_ids = insert_joins_with_confidence!(ItemTag, target, tag_rows)

    snapshot["created_item_ingredient_ids"] = created_ingredient_ids if created_ingredient_ids.any?
    snapshot["created_item_tag_ids"]        = created_tag_ids        if created_tag_ids.any?

    # Re-derive dish confidence after adding new ingredients.
    # May only lower confidence, never raise it.
    if created_ingredient_ids.any?
      old_confidence = target.confidence
      target.reload # refresh denormalized arrays
      new_confidence = derive_item_confidence!(target)
      if new_confidence != old_confidence
        snapshot["confidence"] = [old_confidence, new_confidence]
      end
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

  def apply_section!(target, snapshot)
    return if target.menu_section_id.present?
    return if section_name.blank?

    section = find_or_create_section
    return if section.nil?

    snapshot["menu_section_id"] = [nil, section.id]
    target.update!(menu_section_id: section.id)
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

  # Map payload rows to {node_id, confidence, source} for insertion.
  # Drops unknown slugs (extractor noise must not fail promotion).
  # Each row's source and confidence are mapped per the locked confidence rules.
  def map_joins_with_confidence(model, payload, decided_by:)
    payload_rows = Ingestion::AssociationPayload.load_all(payload)
    return [] if payload_rows.empty?

    # One lookup for all slugs
    slugs = payload_rows.filter_map { |row| row.slug.presence }.uniq
    by_slug = model.where(slug: slugs).pluck(:slug, :id).to_h

    payload_rows.filter_map do |row|
      node_id = by_slug[row.slug]
      next if node_id.nil?

      mapped = Ingestion::ConfidenceMapper.map_row(row, decided_by: decided_by)
      { node_id: node_id, confidence: mapped[:confidence], source: mapped[:source] }
    end
  end

  # Insert join rows with per-row source and confidence.
  # ON CONFLICT DO NOTHING makes it append-only.
  def insert_joins_with_confidence!(model, target, rows)
    return [] if rows.empty?

    foreign_key = model.denormalized_foreign_key
    created = model.insert_all(
      rows.map do |row|
        { item_id: target.id, foreign_key => row[:node_id],
          confidence: row[:confidence], source: row[:source] }
      end,
      unique_by: [:item_id, foreign_key],
      returning: %i[id]
    )
    model.resync_denormalized_ids([target.id])
    created.rows.flatten
  end

  # Compute dish confidence from the item's current ingredient joins (not tags).
  # Only lowers confidence, never raises it.
  def derive_item_confidence!(item)
    ingredient_confidences = item.item_ingredients.pluck(:confidence)
    new_confidence = Ingestion::ConfidenceMapper.dish_confidence_from_ingredients(
      ingredient_confidences.map { |c| { confidence: c } }
    )

    # Never upgrade — a re-scan with better data can't make an item safer
    # than manual review said it was.
    if confidence_rank(new_confidence) < confidence_rank(item.confidence)
      item.update!(confidence: new_confidence)
      new_confidence
    else
      item.confidence
    end
  end

  def confidence_rank(conf)
    { "confirmed" => 3, "suggested" => 2, "inferred" => 1 }[conf] || 0
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
      # Restore ANY confidence change, not just downgrades from confirmed
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

  def find_or_create_section
    return nil if section_name.blank?

    menu = Menu.find_or_create_by!(restaurant: promotion_run.restaurant) do |m|
      m.name = "Main"
      m.position = 0
    end

    MenuSection.find_or_create_by!(menu: menu, name: section_name) do |s|
      s.position = menu.menu_sections.maximum(:position).to_i + 1
    end
  end
end
