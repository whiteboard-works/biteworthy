# frozen_string_literal: true

# Follow-up to 20261013020000 (Codex on #925 / #1018). That backfill
# rewrote pending/edited `ingredients_payload` rows only. `promote!`
# stamps decision=accepted and leaves the payload as scanned; rejected
# rows were never in scope. `undo_staged_item` returns those rows to
# pending without rewriting the payload, so re-accept via promote!
# would recreate an alcohol-root join the celiac presets miss.
#
# An edited update-accept also snapshots the pre-existing alcohol join
# in `applied_changes["replaced_item_ingredient_ids"]`. The live-join
# rewrite moves the current row onto beer; undo restores the snapshot
# onto the published item. Those snapshots are rewritten here too.
#
# This run remaps every decision. Same phrase/normalize/curator rules as
# 20261013020000. Idempotent: a second `up` finds no remaining alcohol
# slugs or snapshot ids on those dishes. `down` does not put them back.
class RewriteRemainingHardSodaPayloads < ActiveRecord::Migration[8.1]
  class MigrationIngredient < ActiveRecord::Base
    self.table_name = "ingredients"
  end

  class MigrationIngestionItem < ActiveRecord::Base
    self.table_name = "ingestion_items"
  end

  MOVED = [ "hard ginger beer", "hard root beer", "spiked root beer" ].freeze
  CURATOR = %w[human owner].freeze

  def up
    alcohol_id = MigrationIngredient.where(slug: "alcohol").pick(:id)
    beer_id    = MigrationIngredient.where(slug: "alcohol-beer").pick(:id)
    unless alcohol_id && beer_id && alcohol_id != beer_id
      say "Taxonomy not seeded; skipping remaining hard-soda payload rewrite"
      return
    end

    rewrite_payloads(alcohol_id, beer_id)
  end

  def down
    # Non-destructive. Restoring the alcohol-root payload would re-open
    # the celiac under-hide this exists to close.
  end

  private

  def rewrite_payloads(alcohol_id, beer_id)
    rewritten = 0
    MigrationIngestionItem.find_each do |staged|
      next unless eligible_text?(staged.name, staged.description, source: "match")

      attrs = {}
      name_has_phrase = phrase_in?(staged.name)
      payload = Array(staged.ingredients_payload)
      updated = remap_payload(payload, name_has_phrase: name_has_phrase)
      attrs[:ingredients_payload] = updated unless updated == payload

      snapshot = staged.applied_changes
      if snapshot.present?
        remapped = remap_snapshot(snapshot, alcohol_id, beer_id, name_has_phrase: name_has_phrase)
        attrs[:applied_changes] = remapped unless remapped == snapshot
      end
      next if attrs.empty?

      staged.update!(attrs)
      rewritten += 1
    end
    say "rewrote #{rewritten} remaining hard-soda payload(s) or undo snapshot(s)" if rewritten.positive?
  end

  def remap_snapshot(snapshot, alcohol_id, beer_id, name_has_phrase:)
    rows = Array(snapshot["replaced_item_ingredient_ids"]).map { |row| stringify_row(row) }
    return snapshot if rows.empty?

    alcohol = alcohol_id.to_s
    beer = beer_id.to_s
    has_beer = rows.any? { |row| row["ingredient_id"].to_s == beer }
    updated = rows.filter_map do |row|
      next row unless row["ingredient_id"].to_s == alcohol
      next row if CURATOR.include?(row["source"].to_s) && !name_has_phrase
      next if has_beer

      has_beer = true
      row.merge("ingredient_id" => beer_id)
    end
    return snapshot if updated == rows

    snapshot.merge("replaced_item_ingredient_ids" => updated)
  end

  def eligible_text?(name, description, source:)
    return false unless phrase_in?("#{name} #{description}")
    return true unless CURATOR.include?(source.to_s)

    phrase_in?(name)
  end

  def phrase_in?(text)
    hay = normalize(text)
    MOVED.any? { |phrase| hay.include?(phrase) }
  end

  # Copied from Ingestion::MenuText.normalize so a later matcher change
  # cannot silently retarget an already-run data migration.
  def normalize(text)
    ActiveSupport::Inflector
      .transliterate(text.to_s.downcase)
      .gsub("&", " and ")
      .tr("-/", "  ")
      .gsub(/[^a-z0-9 ]/, " ")
      .squish
  end

  def remap_payload(payload, name_has_phrase:)
    rows = payload.map { |row| stringify_row(row) }
    has_beer = rows.any? { |row| row["slug"] == "alcohol-beer" }
    rows.filter_map do |row|
      next row unless row["slug"] == "alcohol"
      next row if CURATOR.include?(row["source"].to_s) && !name_has_phrase
      next if has_beer

      has_beer = true
      row.merge("slug" => "alcohol-beer")
    end
  end

  def stringify_row(row)
    row.respond_to?(:to_h) ? row.to_h.stringify_keys : { "slug" => row }
  end
end
