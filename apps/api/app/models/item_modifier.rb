class ItemModifier < ApplicationRecord
  KINDS = %w[choice addition side].freeze
  belongs_to :item
  validates :kind, inclusion: { in: KINDS }
end
