class IngestionItem < ApplicationRecord
  DECISIONS = %w[pending accepted rejected edited].freeze

  belongs_to :ingestion_run
  belongs_to :item, optional: true

  validates :decision, inclusion: { in: DECISIONS }
end
