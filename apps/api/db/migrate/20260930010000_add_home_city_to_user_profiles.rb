# frozen_string_literal: true

# Where the person usually is, so "what's nearby" has an answer without a
# question first. A city, not coordinates: coarse on purpose. Nullified
# rather than blocked if the city goes, since a profile outliving a city
# is fine and a city that cannot be deleted is not.
class AddHomeCityToUserProfiles < ActiveRecord::Migration[8.1]
  def change
    add_reference :user_profiles, :home_city, type: :uuid, null: true,
                  foreign_key: { to_table: :cities, on_delete: :nullify }, index: true
  end
end
