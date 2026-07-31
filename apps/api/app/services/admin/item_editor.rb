# frozen_string_literal: true

# Applies an admin's edits to a live Item. Everything an admin can
# reach through the web /admin item panel lands here so the safety
# rules live in one place:
#
#   - Ingredient/tag joins are synced from slug lists. New rows are
#     `confidence: "confirmed", source: "human"` (an admin IS the
#     trusted source — same convention SuggestionResolver#apply! uses);
#     removals go row-by-row so ItemIngredient/ItemTag's after_destroy
#     callbacks keep the denormalized items.ingredient_ids/tag_ids
#     arrays honest. Never delete_all.
#   - `confidence` on the Item itself is NOT settable here. It moves
#     only through promote! and confirm_community_associations! —
#     strict-mode visibility must stay on those rails.
#   - Variants and modifiers are replaced wholesale from the payload
#     (array order becomes position); they carry no callbacks, so a
#     destroy + recreate inside the transaction is safe.
#
# Raises UnknownSlug (→ 422 with the offenders) rather than silently
# skipping like the ingestion promote path: an admin who typed a bad
# slug deserves to hear about it, whereas the extractor's noise gets
# filtered on purpose.
module Admin
  class ItemEditor
    class UnknownSlug < StandardError
      attr_reader :kind, :slugs

      def initialize(kind, slugs)
        @kind  = kind
        @slugs = slugs
        super("unknown #{kind} slugs: #{slugs.join(', ')}")
      end
    end

    class ForeignSection < StandardError; end

    def initialize(item)
      @item = item
    end

    # `attrs` keys are all optional — an absent key leaves that facet
    # untouched (a PATCH must be able to rename without restating the
    # whole menu row).
    def call(attrs)
      @item.transaction do
        assign_scalars(attrs)
        assign_section(attrs[:menu_section_id]) if attrs.key?(:menu_section_id)
        @item.save!

        sync_ingredients(attrs[:ingredient_slugs]) if attrs.key?(:ingredient_slugs)
        sync_tags(attrs[:tag_slugs])               if attrs.key?(:tag_slugs)
        replace_variants(attrs[:variants])         if attrs.key?(:variants)
        replace_modifiers(attrs[:modifiers])       if attrs.key?(:modifiers)
      end
      @item.reload
    end

    private

    def assign_scalars(attrs)
      %i[name description status].each do |field|
        next unless attrs.key?(field)
        value = attrs[field]
        # Scalar-only: a nested hash would be stringified into the column.
        @item[field] = value if value.nil? || value.is_a?(String)
      end
    end

    # A section from another restaurant would make the item unreachable
    # from its own menu.
    def assign_section(section_id)
      if section_id.blank?
        @item.menu_section_id = nil
        return
      end

      section = MenuSection.joins(:menu).find_by(id: section_id, menus: { restaurant_id: @item.restaurant_id })
      raise ForeignSection, "menu_section #{section_id} belongs to another restaurant" if section.nil?

      @item.menu_section_id = section.id
    end

    def sync_ingredients(slugs)
      wanted = Ingredient.where(slug: Array(slugs).map(&:to_s).uniq)
      assert_all_found!(:ingredient, slugs, wanted)

      current = @item.item_ingredients.includes(:ingredient).index_by { |row| row.ingredient.slug }
      (current.keys - wanted.map(&:slug)).each { |slug| current.fetch(slug).destroy! }
      (wanted.map(&:slug) - current.keys).each do |slug|
        ItemIngredient.create!(
          item: @item, ingredient: wanted.find { |i| i.slug == slug },
          confidence: "confirmed", source: "human"
        )
      end
    end

    def sync_tags(slugs)
      wanted = Tag.where(slug: Array(slugs).map(&:to_s).uniq)
      assert_all_found!(:tag, slugs, wanted)

      current = @item.item_tags.includes(:tag).index_by { |row| row.tag.slug }
      (current.keys - wanted.map(&:slug)).each { |slug| current.fetch(slug).destroy! }
      (wanted.map(&:slug) - current.keys).each do |slug|
        ItemTag.create!(
          item: @item, tag: wanted.find { |t| t.slug == slug },
          confidence: "confirmed", source: "human"
        )
      end
    end

    def assert_all_found!(kind, requested, found)
      missing = Array(requested).map(&:to_s).uniq - found.map(&:slug)
      raise UnknownSlug.new(kind, missing) if missing.any?
    end

    def replace_variants(rows)
      @item.item_variants.destroy_all
      Array(rows).each_with_index do |row, index|
        price = row[:price_cents] || row["price_cents"]
        next if price.blank?

        @item.item_variants.create!(
          size: (row[:size] || row["size"]).presence,
          price_cents: price,
          currency: (row[:currency] || row["currency"]).presence || "USD",
          position: index
        )
      end
    end

    def replace_modifiers(rows)
      @item.item_modifiers.destroy_all
      Array(rows).each do |row|
        name = (row[:name] || row["name"]).to_s.strip
        next if name.empty?

        @item.item_modifiers.create!(
          name: name,
          kind: (row[:kind] || row["kind"]).presence || "addition",
          price_cents: (row[:price_cents] || row["price_cents"]).presence
        )
      end
    end
  end
end
