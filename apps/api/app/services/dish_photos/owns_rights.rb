# frozen_string_literal: true

module DishPhotos
  # `owns_rights` is a diner's confirmation that they took the photo.
  # ActiveModel::Type::Boolean treats any non-falsey string as true, so
  # "banana" would pass. Only true / "true" / "1" / 1.
  module OwnsRights
    ACCEPTED = [ true, "true", "1", 1 ].freeze

    def self.accepted?(value)
      ACCEPTED.include?(value)
    end
  end
end
