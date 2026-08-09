class ItemTag < ApplicationRecord
  include SyncsDenormalizedIds

  CONFIDENCE = %w[confirmed suggested inferred].freeze
  SOURCES    = %w[human ai owner].freeze

  belongs_to :item
  belongs_to :tag

  validates :confidence, inclusion: { in: CONFIDENCE }
  validates :source,     inclusion: { in: SOURCES }

  denormalizes column: :tag_ids, foreign_key: :tag_id
end
