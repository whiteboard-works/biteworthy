class AddTimestampsToDietaryProfileJoins < ActiveRecord::Migration[8.1]
  # The only two tables in the schema with no timestamps. These rows
  # define what a curated preset (Celiac, Vegan, …) avoids, so "when
  # did this preset change, and did a user's filter change under
  # them?" is a question worth being able to answer.
  #
  # Existing rows get the migration time — the presets are seeded, so
  # that is close enough to their real creation date to be useful and
  # honest as an upper bound.
  def change
    %i[dietary_profile_ingredients dietary_profile_tags].each do |table|
      add_timestamps table, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
  end
end
