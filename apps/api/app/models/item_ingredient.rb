class ItemIngredient < ApplicationRecord
  CONFIDENCE = %w[confirmed suggested inferred].freeze
  SOURCES    = %w[human ai owner].freeze

  belongs_to :item
  belongs_to :ingredient

  validates :confidence, inclusion: { in: CONFIDENCE }
  validates :source,     inclusion: { in: SOURCES }

  after_save    :sync_item_ingredient_ids
  after_destroy :sync_item_ingredient_ids

  private

  # Keep the denormalized array on items in lockstep with this join.
  # The array is what GIN-indexed filter queries hit — the join table
  # is only the source of truth + audit log.
  def sync_item_ingredient_ids
    ids = item.item_ingredients.pluck(:ingredient_id)
    item.update_columns(ingredient_ids: ids, updated_at: Time.current)
  end
end
