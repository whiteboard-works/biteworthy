class AddEnumCheckConstraints < ActiveRecord::Migration[8.1]
  # Every one of these columns is a bare string whose allowed values
  # live only in a Ruby `validates :inclusion` — which `update_all`,
  # `update_columns`, `upsert_all`, and a psql session all bypass.
  # `Restaurant#confirm_community_associations!` writes `confidence`
  # through `update_all` today, so this is not hypothetical.
  #
  # Added NOT VALID: Postgres enforces them on every INSERT and UPDATE
  # from here on, but does not scan the existing table. That keeps the
  # deploy instant and lock-free, and means a legacy row nobody has
  # audited yet cannot abort the migration. Promoting them to VALID is
  # a follow-up (see docs/roadmap.md) once prod data is confirmed
  # clean — `VALIDATE CONSTRAINT` takes only a SHARE UPDATE EXCLUSIVE
  # lock, so it can happen any time.
  #
  # The literals are deliberately duplicated from the model constants
  # rather than interpolated: a migration must keep meaning even after
  # the model moves on. `spec/models/enum_check_constraints_spec.rb`
  # asserts the two never drift apart.
  CONSTRAINTS = {
    "items"            => { "status"            => %w[draft published removed],
                            "confidence"        => %w[confirmed suggested inferred] },
    "item_ingredients" => { "confidence"        => %w[confirmed suggested inferred],
                            "source"            => %w[human ai owner] },
    "item_tags"        => { "confidence"        => %w[confirmed suggested inferred],
                            "source"            => %w[human ai owner] },
    "item_modifiers"   => { "kind"              => %w[choice addition side] },
    "restaurants"      => { "status"            => %w[draft published closed] },
    "user_profiles"    => { "strictness"        => %w[relaxed balanced strict] },
    "ingestion_runs"   => { "status"            => %w[queued extracting resolving staged published failed],
                            "input_kind"        => %w[photo url pdf text],
                            "enrichment_status" => %w[pending completed failed] },
    "ingestion_items"  => { "decision"          => %w[pending accepted rejected edited] },
    "tags"             => { "family"            => %w[diet allergen cuisine prep flavor] },
    "suggestions"      => { "status"            => %w[pending accepted rejected] },
    "dmca_notices"     => { "status"            => %w[received actioned rejected] },
    "waitlist_signups" => { "source"            => %w[landing press footer mobile_app] }
  }.freeze

  # Nullable columns: the constraint has to permit NULL explicitly.
  NULLABLE = {
    "reviews" => { "hidden_reason" => %w[spam abuse duplicate off_topic] }
  }.freeze

  def change
    CONSTRAINTS.each do |table, columns|
      columns.each do |column, values|
        add_check_constraint table,
                             "#{column} IN (#{values.map { |v| "'#{v}'" }.join(', ')})",
                             name: "#{table}_#{column}_valid", validate: false
      end
    end

    NULLABLE.each do |table, columns|
      columns.each do |column, values|
        add_check_constraint table,
                             "#{column} IS NULL OR #{column} IN (#{values.map { |v| "'#{v}'" }.join(', ')})",
                             name: "#{table}_#{column}_valid", validate: false
      end
    end

    # Mirrors `validates :day_of_week, inclusion: { in: 0..6 }`.
    add_check_constraint :hours, "day_of_week BETWEEN 0 AND 6",
                         name: "hours_day_of_week_valid", validate: false
  end
end
