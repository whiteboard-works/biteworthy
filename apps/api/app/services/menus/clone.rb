# frozen_string_literal: true

module Menus
  # Copy published dishes from one restaurant onto an empty sibling.
  # Address, hours, and phone stay on each Restaurant row — this only
  # clones the menu. No brand-parent table: the caller names both slugs.
  #
  # Joins are written as join rows (never `items.ingredient_ids` /
  # `items.tag_ids` directly) so SyncsDenormalizedIds keeps the arrays
  # honest. Confidence and source are copied as-is: a confirmed Caracas
  # dish stays confirmed; a community-accepted suggested dish stays
  # suggested.
  class Clone
    class Error < StandardError; end

    Result = Struct.new(:items_cloned, :sections_cloned, :source, :target, keyword_init: true)

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

      Result.new(
        items_cloned:    items_cloned,
        sections_cloned: section_map.size,
        source:          { id: @source.id, slug: @source.slug, name: @source.name },
        target:          { id: @target.id, slug: @target.slug, name: @target.name }
      )
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
             .includes(:item_ingredients, :item_tags, :item_variants, :item_modifiers, menu_section: :menu)
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
      clone = Item.create!(
        restaurant:         @target,
        menu_section:       section,
        name:               item.name,
        description:        item.description,
        status:             item.status,
        confidence:         item.confidence,
        position:           item.position,
        created_by_user_id: @actor&.id
      )

      item.item_ingredients.each do |join|
        ItemIngredient.create!(
          item: clone, ingredient_id: join.ingredient_id,
          confidence: join.confidence, source: join.source
        )
      end
      item.item_tags.each do |join|
        ItemTag.create!(
          item: clone, tag_id: join.tag_id,
          confidence: join.confidence, source: join.source
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
      clone.photo.attach(item.photo.blob) if item.photo.attached?
      clone
    end
  end
end
