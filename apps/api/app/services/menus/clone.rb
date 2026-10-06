# frozen_string_literal: true

module Menus
  # Copy published dishes from one restaurant onto an empty sibling.
  # Address, hours, and phone stay on each Restaurant row — this only
  # clones the menu. No brand-parent table: the caller names both slugs.
  #
  # Joins are written as join rows (never `items.ingredient_ids` /
  # `items.tag_ids` directly) so SyncsDenormalizedIds keeps the arrays
  # honest.
  #
  # Trust matches a community accept: a non-admin clone writes item and
  # join confidence at `suggested`, never higher than the source. A
  # confirmed dish at location A is not human-confirmed at location B.
  # Admin clones keep confidence as-is.
  #
  # The whole copy runs in one transaction so a mid-clone failure cannot
  # leave the target half-filled (the empty-menu guard would then block
  # retry). Photos are copied as new blobs — sharing one blob would let
  # a later purge/replace on either item delete the other's file.
  #
  # A published source publishes the target. Clone has no ingestion run,
  # so `IngestionRun#maybe_publish!` would never fire and a community
  # sibling would stay draft (invisible in search) forever.
  class Clone
    class Error < StandardError; end

    Result = Struct.new(:items_cloned, :sections_cloned, :source, :target, keyword_init: true)

    # Weaker first. A community clone may keep `inferred` but must not
    # write anything stronger than `suggested`.
    CONFIDENCE_RANK = { "inferred" => 0, "suggested" => 1, "confirmed" => 2 }.freeze

    def self.call(source:, target:, actor:)
      new(source: source, target: target, actor: actor).call
    end

    def initialize(source:, target:, actor:)
      @source = source
      @target = target
      @actor  = actor
    end

    def call
      authorize!
      dishes = source_dishes
      raise Error, "The source restaurant has no published dishes to clone." if dishes.empty?

      result = nil
      ActiveRecord::Base.transaction do
        if @target.items.exists?
          raise Error, "The target restaurant already has dishes. Clone only onto an empty menu."
        end

        items_cloned = 0
        section_map  = {}

        Item.defer_denormalization do
          dishes.each do |item|
            clone_item!(item, section_for(item.menu_section, section_map))
            items_cloned += 1
          end
        end

        publish_target_if_source_live!

        result = Result.new(
          items_cloned:    items_cloned,
          sections_cloned: section_map.size,
          source:          restaurant_payload(@source),
          target:          restaurant_payload(@target.reload)
        )
      end
      result
    end

    private

    def authorize!
      raise Error, "You can only clone from a published restaurant or one you created." unless readable?(@source)
      raise Error, "You can only clone onto a restaurant you created." unless writable?(@target)
      raise Error, "Source and target must be different restaurants." if @source.id == @target.id
    end

    def readable?(restaurant)
      return true if @actor&.is_admin?
      return true if restaurant.status == "published"

      restaurant.status == "draft" && restaurant.created_by_user_id == @actor&.id
    end

    def writable?(restaurant)
      return true if @actor&.is_admin?

      restaurant.created_by_user_id == @actor&.id
    end

    def source_dishes
      @source.items.published
             .with_attached_photo
             .includes(:item_ingredients, :item_tags, :item_variants, :item_modifiers,
                       menu_section: :menu)
             .order(:position, :name)
             .to_a
    end

    def section_for(section, section_map)
      return nil if section.nil?

      section_map[section.id] ||= begin
        menu = Menu.find_or_create_by!(restaurant: @target, name: section.menu&.name.presence || "Main") do |row|
          row.position = section.menu&.position.to_i
          row.description = section.menu&.description
        end
        MenuSection.create!(
          menu: menu, name: section.name, description: section.description, position: section.position
        )
      end
    end

    def clone_item!(item, section)
      confidence = clone_confidence(item.confidence)
      clone = Item.create!(
        restaurant:         @target,
        menu_section:       section,
        name:               item.name,
        description:        item.description,
        status:             item.status,
        confidence:         confidence,
        position:           item.position,
        created_by_user_id: @actor&.id
      )

      item.item_ingredients.each do |join|
        ItemIngredient.create!(
          item: clone, ingredient_id: join.ingredient_id,
          confidence: clone_confidence(join.confidence), source: join.source
        )
      end
      item.item_tags.each do |join|
        ItemTag.create!(
          item: clone, tag_id: join.tag_id,
          confidence: clone_confidence(join.confidence), source: join.source
        )
      end
      item.item_variants.each do |variant|
        ItemVariant.create!(
          item: clone, size: variant.size, price_cents: variant.price_cents,
          currency: variant.currency, position: variant.position
        )
      end
      item.item_modifiers.each do |modifier|
        ItemModifier.create!(
          item: clone, name: modifier.name, kind: modifier.kind,
          price_cents: modifier.price_cents,
          ingredient_ids: modifier.ingredient_ids, tag_ids: modifier.tag_ids
        )
      end
      copy_photo!(item, clone)
      clone
    end

    def clone_confidence(value)
      return value if @actor&.is_admin?

      [ value, "suggested" ].min_by { |confidence| CONFIDENCE_RANK.fetch(confidence, -1) }
    end

    # New blob, same bytes. `attach(blob)` would share one file, and
    # ItemEditor / DishPhotos::Moderate purge the replaced blob without
    # checking other attachments (`purge_later` / `dependent: :purge_later`).
    def copy_photo!(item, clone)
      return unless item.photo.attached?

      blob = item.photo.blob
      clone.photo.attach(
        io:           StringIO.new(item.photo.download),
        filename:     blob.filename,
        content_type: blob.content_type
      )
    end

    def publish_target_if_source_live!
      return unless @source.status == "published"
      return if @target.status == "published"

      @target.update!(status: "published")
    end

    def restaurant_payload(restaurant)
      { id: restaurant.id, slug: restaurant.slug, name: restaurant.name, status: restaurant.status }
    end
  end
end
