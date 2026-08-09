class ItemIngredient < ApplicationRecord
  include SyncsDenormalizedIds

  CONFIDENCE = %w[confirmed suggested inferred].freeze
  SOURCES    = %w[human ai owner].freeze

  belongs_to :item
  belongs_to :ingredient

  validates :confidence, inclusion: { in: CONFIDENCE }
  validates :source,     inclusion: { in: SOURCES }

  denormalizes column: :ingredient_ids, foreign_key: :ingredient_id
end
