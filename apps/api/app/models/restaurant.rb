class Restaurant < ApplicationRecord
  STATUSES = %w[draft published closed].freeze

  belongs_to :city
  belongs_to :claimed_by_user, class_name: "User", optional: true
  # Phase 6.2 — community-created restaurants record their creator;
  # admin/seed-created rows leave this nil.
  belongs_to :created_by_user, class_name: "User", optional: true

  has_many :addresses,     dependent: :destroy
  has_many :hours,         dependent: :destroy
  has_many :menus,         dependent: :destroy
  has_many :menu_sections, through: :menus
  has_many :items,         dependent: :destroy

  validates :slug, :name, presence: true
  validates :slug, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :published, -> { where(status: "published") }
  # Phase 6.4 — the moderation lens. Two ways a restaurant enters it:
  # a community member created it (created_by_user_id present), OR a
  # community member re-scanned an existing/seeded restaurant, which
  # leaves `suggested` items behind (6.4.1 — codex caught that
  # rescans escaped the creator-only version of this scope).
  scope :community_published, -> {
    published.where(
      "restaurants.created_by_user_id IS NOT NULL OR EXISTS (
         SELECT 1 FROM items
         WHERE items.restaurant_id = restaurants.id
           AND items.confidence = 'suggested'
       )"
    )
  }

  # Phase 6.4 — graduate a community-verified menu to strict-mode
  # visibility: flip every `suggested` association a HUMAN vouched for
  # to `confirmed`, plus the items' own confidence. Deliberately does
  # NOT touch `source: ai` rows — the admin is endorsing the human
  # verifier's judgment, not the model's unreviewed guesses.
  #
  # update_all is safe here: the join callbacks only sync the
  # denormalized id arrays, and no ids change.
  #
  # Returns counts for the admin-facing confirmation message.
  def confirm_community_associations!
    transaction do
      ingredients_n = ItemIngredient.joins(:item)
                                    .where(items: { restaurant_id: id },
                                           confidence: "suggested", source: "human")
                                    .update_all(confidence: "confirmed")
      tags_n        = ItemTag.joins(:item)
                             .where(items: { restaurant_id: id },
                                    confidence: "suggested", source: "human")
                             .update_all(confidence: "confirmed")

      # Only items whose EVERY association is now confirmed graduate —
      # an item still carrying an ai-suggested join must stay
      # `suggested`, or strict mode would show it while an untrusted
      # association remains (6.4.1 — codex).
      items_n = items.where(confidence: "suggested")
                     .where.not(id: ItemIngredient.where(confidence: "suggested").select(:item_id))
                     .where.not(id: ItemTag.where(confidence: "suggested").select(:item_id))
                     .update_all(confidence: "confirmed")

      { items: items_n, ingredients: ingredients_n, tags: tags_n }
    end
  end

  # SEO-friendly URLs (`/restaurants/ninis-1`) need lookup-by-slug;
  # mobile/api consumers still pass UUIDs. Single endpoint accepts
  # either by sniffing the value.
  UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  def self.find_by_id_or_slug!(value)
    if value.to_s.match?(UUID_FORMAT)
      find(value)
    else
      find_by!(slug: value)
    end
  end
end
