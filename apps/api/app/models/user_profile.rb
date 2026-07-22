class UserProfile < ApplicationRecord
  STRICTNESS = %w[relaxed balanced strict].freeze

  # Phase 8.1 — the four taste-signal arrays. Taste is SOFT: it ranks
  # the safe items (Top Picks), it never hides. The avoid arrays are
  # the hard safety filter; an id present in an avoid list is simply
  # ignored by scoring (filter wins — not a validation error).
  TASTE_FIELDS = {
    liked_ingredient_ids:    :ingredient,
    liked_tag_ids:           :tag,
    disliked_ingredient_ids: :ingredient,
    disliked_tag_ids:        :tag
  }.freeze

  belongs_to :user
  belongs_to :primary_dietary_profile, class_name: "DietaryProfile", optional: true

  validates :strictness, inclusion: { in: STRICTNESS }
  validate :taste_signals_disjoint
  validate :taste_ids_exist

  private

  # "I love it AND I hate it" is a client bug, not a preference —
  # scoring would silently cancel the terms out. Fail loud instead.
  def taste_signals_disjoint
    if (liked_ingredient_ids & disliked_ingredient_ids).any?
      errors.add(:liked_ingredient_ids, "cannot also appear in disliked_ingredient_ids")
    end
    if (liked_tag_ids & disliked_tag_ids).any?
      errors.add(:liked_tag_ids, "cannot also appear in disliked_tag_ids")
    end
  end

  # Only validate a taste array that this save actually changes. The
  # goal is to catch a client sending a bad/typo'd UUID — not to
  # re-check arrays we're leaving alone. Re-checking untouched arrays
  # meant a partial PATCH (e.g. just `strictness`) would 422 whenever a
  # stored taste id had gone stale (its taxonomy node was later removed
  # by an admin), soft-locking the user out of editing ANY preference,
  # including their safety filter. GET already tolerates stale ids by
  # dropping them on read; writes must be just as forgiving of arrays
  # they don't touch.
  def taste_ids_exist
    TASTE_FIELDS.each do |attr, kind|
      next unless will_save_change_to_attribute?(attr)

      ids = self[attr].compact.uniq
      next if ids.empty?

      klass   = kind == :ingredient ? Ingredient : Tag
      missing = ids - klass.where(id: ids).pluck(:id)
      errors.add(attr, "contains unknown #{kind} ids: #{missing.join(', ')}") if missing.any?
    end
  end
end
