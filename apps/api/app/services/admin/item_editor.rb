# frozen_string_literal: true

# Applies an admin's edits to a live Item. Everything an admin can
# reach through the web /admin item panel lands here so the safety
# rules live in one place:
#
#   - Ingredient/tag joins are synced from slug lists. New rows default
#     to `confidence: "confirmed", source: "human"` (an admin IS the
#     trusted source — same convention SuggestionResolver#apply! uses).
#     Pass `added_confidence: "suggested"` or `"inferred"` to mark only
#     the rows ADDED in that request as a cautionary guess. Those land
#     `source: "derived"` so ConfidenceMapper's TRUSTED_SOURCES
#     (match/human/owner) will never remap them to confirmed — `derived`
#     is the existing check-constraint value for name/keyword inference,
#     and map_confidence always keeps it at suggested. Kept rows are
#     left untouched. Removals go row-by-row so ItemIngredient/ItemTag's
#     after_destroy callbacks keep the denormalized items.ingredient_ids/
#     tag_ids arrays honest (rebuilt once for the whole edit, not once
#     per row — see Item.defer_denormalization). Never delete_all.
#   - `confidence` on the Item itself is NOT settable here. After a join
#     sync it is re-derived from the weakest current join row (ingredients
#     AND tags, only ever downgraded) so a suggested contains-gluten tag
#     pulls a confirmed dish down to suggested. Graduation still belongs
#     to promote! / confirm_community_associations!.
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

    class InvalidAddedConfidence < StandardError
      attr_reader :value

      def initialize(value)
        @value = value
        super("invalid added_confidence: #{value}")
      end
    end

    # Unverified admin adds use `derived`, not `human`. TRUSTED_SOURCES
    # is match/human/owner — a later remap of a human row would confirm
    # it. `derived` is already on the join check constraints and is the
    # PR 793 source for a name/keyword guess (pizza → wheat).
    UNVERIFIED_SOURCE = "derived"

    def initialize(item)
      @item = item
    end

    # `attrs` keys are all optional — an absent key leaves that facet
    # untouched (a PATCH must be able to rename without restating the
    # whole menu row).
    def call(attrs)
      added_confidence = resolve_added_confidence(attrs[:added_confidence])

      @item.transaction do
        assign_scalars(attrs)
        assign_section(attrs[:menu_section_id]) if attrs.key?(:menu_section_id)
        handle_photo(attrs)
        @item.save!

        synced = false
        Item.defer_denormalization do
          if attrs.key?(:ingredient_slugs)
            sync_ingredients(attrs[:ingredient_slugs], added_confidence)
            synced = true
          end
          if attrs.key?(:tag_slugs)
            sync_tags(attrs[:tag_slugs], added_confidence)
            synced = true
          end
        end
        rederive_item_confidence! if synced
        replace_variants(attrs[:variants])         if attrs.key?(:variants)
        replace_modifiers(attrs[:modifiers])       if attrs.key?(:modifiers)
      end
      @item.reload
    end

    private

    def assign_scalars(attrs)
      %i[name description status position].each do |field|
        next unless attrs.key?(field)
        value = attrs[field]
        # position is an integer; others are strings
        if field == :position
          @item[field] = value.to_i if value.present?
        else
          @item[field] = value if value.nil? || value.is_a?(String)
        end
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

    # Photo can be attached via direct upload (multipart file), signed blob
    # id (from POST /attachments), or removed with a flag. Attach before
    # save! so validation errors surface as 422 instead of silently failing.
    # Preprocess the card variant after attachment for faster first load.
    def handle_photo(attrs)
      if attrs[:remove_photo].to_s == "true"
        # Use purge_later to avoid blocking the transaction
        @item.photo.purge_later if @item.photo.attached?
        @item.photo_submission_id = nil
        return
      end

      preprocess = false
      if attrs[:photo].respond_to?(:tempfile)
        @item.photo.attach(
          io:           attrs[:photo].tempfile,
          filename:     attrs[:photo].original_filename.presence || "dish.jpg",
          content_type: attrs[:photo].content_type.presence
        )
        @item.photo_submission_id = nil
        preprocess = true
      elsif attrs[:photo_signed_id].present?
        @item.photo.attach(attrs[:photo_signed_id])
        @item.photo_submission_id = nil
        # Skip preprocessing for signed_id - the blob is already stored and
        # variants will be generated on first access
      end

      # Preprocess the card variant for faster menu page loads. Only for direct
      # uploads since signed_id blobs are already stored. Rescue all errors since
      # preprocessing is optional (it just speeds up first access).
      if preprocess && @item.photo.attached?
        begin
          @item.photo.variant(:card).processed
        rescue => e
          Rails.logger.warn("Variant preprocessing failed: #{e.class} #{e.message}")
        end
      end
    end

    def sync_ingredients(slugs, added_confidence)
      wanted = Ingredient.where(slug: Array(slugs).map(&:to_s).uniq)
      assert_all_found!(:ingredient, slugs, wanted)

      current = @item.item_ingredients.includes(:ingredient).index_by { |row| row.ingredient.slug }
      (current.keys - wanted.map(&:slug)).each { |slug| current.fetch(slug).destroy! }
      (wanted.map(&:slug) - current.keys).each do |slug|
        ItemIngredient.create!(
          item: @item, ingredient: wanted.find { |i| i.slug == slug },
          **added_join_attrs(added_confidence)
        )
      end
    end

    def sync_tags(slugs, added_confidence)
      wanted = Tag.where(slug: Array(slugs).map(&:to_s).uniq)
      assert_all_found!(:tag, slugs, wanted)

      current = @item.item_tags.includes(:tag).index_by { |row| row.tag.slug }
      (current.keys - wanted.map(&:slug)).each { |slug| current.fetch(slug).destroy! }
      (wanted.map(&:slug) - current.keys).each do |slug|
        ItemTag.create!(
          item: @item, tag: wanted.find { |t| t.slug == slug },
          **added_join_attrs(added_confidence)
        )
      end
    end

    def resolve_added_confidence(value)
      return "confirmed" if value.nil? || value.to_s.strip.empty?

      confidence = value.to_s
      raise InvalidAddedConfidence, confidence unless Item::CONFIDENCE.include?(confidence)

      confidence
    end

    def added_join_attrs(added_confidence)
      if added_confidence == "confirmed"
        { confidence: "confirmed", source: "human" }
      else
        { confidence: added_confidence, source: UNVERIFIED_SOURCE }
      end
    end

    # Weakest current join row, ingredients AND tags. Empty lists stay
    # suggested. Only ever lowers — graduation is confirm_community.
    # Tags count here (unlike promote's ingredient-only dish score)
    # because an admin-added cautionary allergen tag is why this path
    # exists: a suggested contains-gluten must unconfirm the dish.
    def rederive_item_confidence!
      rows = @item.item_ingredients.reload.pluck(:confidence) +
             @item.item_tags.reload.pluck(:confidence)
      weakest = if rows.empty?
        "suggested"
      else
        rows.max_by { |c| Item::CONFIDENCE.index(c) || -1 }
      end

      current_idx = Item::CONFIDENCE.index(@item.confidence) || 1
      weakest_idx = Item::CONFIDENCE.index(weakest) || 1
      @item.update!(confidence: weakest) if weakest_idx > current_idx
    end

    def assert_all_found!(kind, requested, found)
      missing = Array(requested).map(&:to_s).uniq - found.map(&:slug)
      raise UnknownSlug.new(kind, missing) if missing.any?
    end

    def replace_variants(rows)
      @item.item_variants.destroy_all
      Array(rows).each_with_index do |row, index|
        price = (row[:price_cents] || row["price_cents"]).presence
        size  = (row[:size] || row["size"]).presence
        # A size with no amount is a real menu row ("Large — market
        # price"), and re-scan writes them. Only a wholly empty row is
        # noise worth dropping.
        next if price.nil? && size.nil?

        @item.item_variants.create!(
          size: size,
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
