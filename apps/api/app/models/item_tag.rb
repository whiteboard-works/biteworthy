class ItemTag < ApplicationRecord
  CONFIDENCE = %w[confirmed suggested inferred].freeze
  SOURCES    = %w[human ai owner].freeze

  belongs_to :item
  belongs_to :tag

  validates :confidence, inclusion: { in: CONFIDENCE }
  validates :source,     inclusion: { in: SOURCES }

  after_save    :sync_item_tag_ids
  after_destroy :sync_item_tag_ids

  private

  def sync_item_tag_ids
    ids = item.item_tags.pluck(:tag_id)
    item.update_columns(tag_ids: ids, updated_at: Time.current)
  end
end
