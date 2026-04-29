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

      update!(item: created, decision: "accepted", decided_at: Time.current)
      created
    end
  end
end
