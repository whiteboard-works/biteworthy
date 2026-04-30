class IngestionItem < ApplicationRecord
  DECISIONS = %w[pending accepted rejected edited].freeze

  belongs_to :ingestion_run
  belongs_to :item, optional: true

  validates :decision, inclusion: { in: DECISIONS }

  DECISIONS.each do |d|
    define_method("#{d}?") { decision == d }
  end

  # Materialize a staged ingestion item into a real Item +
  # ItemIngredient + ItemTag join rows. Called from the swipe-verify
  # UI (Phase 2.5) once a human has accepted (or edited then accepted)
  # the AI's suggestion. The new associations are saved with
  # `confidence: confirmed, source: human` because at this point a
  # human has explicitly signed off.
  #
  # Idempotent: re-calling on an already-promoted IngestionItem
  # returns the existing Item without creating duplicates.
  #
  # Returns the materialized Item; raises if the run has no
  # restaurant attached (which means we don't know where to put it).
  def promote!
    return item if item.present?
    raise "IngestionRun ##{ingestion_run_id} has no restaurant" if ingestion_run.restaurant_id.blank?

    transaction do
      created = Item.create!(
        restaurant: ingestion_run.restaurant,
        name:        name,
        description: description.presence,
        status:      "published",
        confidence:  "confirmed"
      )

      Array(ingredients_payload).each do |row|
        slug = row["slug"] || row[:slug]
        next if slug.blank?
        ingredient = Ingredient.find_by(slug: slug)
        next if ingredient.nil?

        ItemIngredient.create!(
          item: created, ingredient: ingredient,
          confidence: "confirmed", source: "human"
        )
      end

      Array(tags_payload).each do |row|
        slug = row["slug"] || row[:slug]
        next if slug.blank?
        tag = Tag.find_by(slug: slug)
        next if tag.nil?

        ItemTag.create!(
          item: created, tag: tag,
          confidence: "confirmed", source: "human"
        )
      end

      attach_dish_photo!(created)

      update!(item: created, decision: "accepted", decided_at: Time.current)
      created
    end
  end

  private

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
