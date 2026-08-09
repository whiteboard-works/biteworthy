module Ingestion
  # Pure diff between a staged IngestionItem's payloads and the live Item
  # its matcher link points at. Computed at serialize time, never stored:
  # gap-fill appends ingredient rows after the run is already :staged, so
  # a stored diff would go stale the moment enrichment lands.
  #
  # Absence of evidence is never a change: a blank scanned description or
  # an empty scanned price set yields nil for that field rather than
  # proposing a blank-out/delete.
  class ItemUpdateDiff
    def self.call(ingestion_item, item)
      description = description_change(ingestion_item, item)
      prices = prices_change(ingestion_item, item)
      added_ingredients = added_slugs(ingestion_item.ingredients_payload, item.ingredients)
      added_tags = added_slugs(ingestion_item.tags_payload, item.tags)

      {
        description: description,
        prices: prices,
        added_ingredients: added_ingredients,
        added_tags: added_tags,
        no_changes: description.nil? && prices.nil? &&
          added_ingredients.empty? && added_tags.empty?
      }
    end

    # Canonical price shape for comparison and display: priceless rows
    # dropped (a bare size is noise), stable sort so payload order vs
    # variant position order can't fake a change.
    def self.normalize_prices(rows)
      Array(rows).filter_map do |row|
        row = row.with_indifferent_access if row.respond_to?(:with_indifferent_access)
        cents = row[:price_cents]
        next if cents.blank?

        { size: row[:size].presence, price_cents: cents.to_i }
      end.sort_by { |r| [r[:price_cents], r[:size].to_s] }
    end

    def self.description_change(ingestion_item, item)
      scanned = ingestion_item.description.to_s.strip
      return nil if scanned.blank?
      return nil if scanned == item.description.to_s.strip

      { from: item.description, to: ingestion_item.description }
    end
    private_class_method :description_change

    def self.prices_change(ingestion_item, item)
      to = normalize_prices(ingestion_item.prices_payload)
      return nil if to.empty?

      from = normalize_prices(
        item.item_variants.map { |v| { size: v.size, price_cents: v.price_cents } }
      )
      return nil if from == to

      { from: from, to: to }
    end
    private_class_method :prices_change

    def self.added_slugs(payload, existing_records)
      existing = existing_records.map(&:slug)
      AssociationPayload.load_all(payload).filter_map(&:slug).uniq - existing
    end
    private_class_method :added_slugs
  end
end
