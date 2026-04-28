class IngestionRun < ApplicationRecord
  INPUT_KINDS = %w[photo url pdf].freeze
  STATUSES    = %w[queued extracting resolving staged published failed].freeze

  belongs_to :user, optional: true
  belongs_to :restaurant, optional: true
  has_many :ingestion_items, dependent: :destroy

  validates :input_kind, inclusion: { in: INPUT_KINDS }
  validates :status,     inclusion: { in: STATUSES }
end
