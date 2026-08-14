class Item < ApplicationRecord
  include HasPhotoValidation

  # Step one of dropping `popularity`, which nothing ever wrote. The
  # column is still there; this release simply stops reading it, and a
  # follow-up migration removes it.
  #
  # **The split is not ceremony.** `bin/docker-entrypoint` runs
  # `db:prepare` when the new puma container boots, and `deploy.yml` says
  # in as many words that kamal-proxy keeps traffic on the *old* release
  # until the new one's healthcheck passes. So a migration and the code
  # that stops needing it in one release means the old container answers
  # menu requests with `ORDER BY items.popularity` against a column that
  # is already gone — `PG::UndefinedColumn` on the product's busiest read
  # path, for the length of every deploy window.
  #
  # `ignored_columns` is what makes the follow-up safe in the other
  # direction too: Rails builds INSERT and UPDATE column lists from the
  # cached schema, so a container that still believes in the column would
  # write it. Listed here, it does not exist as far as this release is
  # concerned. Caught by Codex on #601.
  self.ignored_columns += %w[popularity]

  STATUSES   = %w[draft published removed].freeze
  CONFIDENCE = %w[confirmed suggested inferred].freeze

  belongs_to :restaurant
  belongs_to :menu_section, optional: true
  belongs_to :created_by_user, class_name: "User", optional: true

  has_many :item_variants,    dependent: :destroy
  has_many :item_modifiers,   dependent: :destroy
  has_many :item_ingredients, dependent: :destroy
  has_many :ingredients, through: :item_ingredients
  has_many :item_tags,        dependent: :destroy
  has_many :tags,        through: :item_tags
  has_many :reviews,          dependent: :destroy
  has_many :user_item_overrides, dependent: :destroy
  has_many :favorite_items,   dependent: :destroy
  # Destroying a promoted item used to raise InvalidForeignKey —
  # `ingestion_items.item_id` had no association at all, unlike its
  # sibling `matched_item_id`, which nullifies at the database level.
  #
  # Destroy rather than nullify, though `nullify` was the first
  # instinct: `decision: "accepted"` with `item_id: nil` is exactly the
  # shape two paths read as "accepted but not yet promoted".
  # `ReExtractRun` would stop raising `HasPromotedItems` and let the run
  # rewind, and `ResolveRun#promote_accepted_items!` would re-create the
  # item an admin had just deleted. A staged row whose item is gone has
  # no decision left to represent.
  has_many :ingestion_items,  dependent: :destroy
  # `suggestions.subject` is polymorphic, so there is no foreign key to
  # stop this and no association to cascade it — a hard delete left the
  # suggestion behind, and `belongs_to :subject` is required, so the
  # orphan could never even be rejected ("Subject must exist") while
  # still counting in the dashboard's pending queue. Restaurant claims
  # are suggestions with a Restaurant subject, which is how a claimed
  # restaurant could strand its own claim forever.
  has_many :suggestions, as: :subject, dependent: :destroy

  has_one_attached :photo

  validates :name, presence: true
  validates :status,     inclusion: { in: STATUSES }
  validates :confidence, inclusion: { in: CONFIDENCE }

  scope :published, -> { where(status: "published") }

  # `item.ingredient_ids` / `item.tag_ids` resolve to the has_many-through
  # readers, which SHADOW the identically-named denormalized columns and
  # cost a query per item unless the association is preloaded. These read
  # the columns the join callbacks keep in sync — free, and the same
  # arrays `Cities::RestaurantRanking` and `TasteScoring` hit in SQL.
  # Read paths that don't already need the join rows should use these.
  def denormalized_ingredient_ids
    read_attribute(:ingredient_ids)
  end

  def denormalized_tag_ids
    read_attribute(:tag_ids)
  end

  # Bulk writers attach many joins to the same item, and every join rewrites
  # the whole array. Inside this block the touched items are collected and
  # each array is rebuilt once, before the block's transaction commits.
  def self.defer_denormalization(&block)
    SyncsDenormalizedIds.defer(&block)
  end
end
