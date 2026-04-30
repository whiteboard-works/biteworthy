# Phase 4.10 — accept/reject community-edit suggestions on Items.
#
# The Suggestion polymorphic queue handles many flavors of edit. This
# resolver knows how to TURN AN ACCEPT INTO A REAL CHANGE — adding /
# removing ItemIngredient + ItemTag join rows, renaming items, etc.
# Mirrors IngestionItem#promote! semantics: accepted edits land as
# `confidence: confirmed, source: human` so they outweigh any future
# AI re-ingestion.
#
# Rejecting is just a status change — no side effects on the Item.
class SuggestionResolver
  ITEM_KINDS = %w[
    add_ingredient
    remove_ingredient
    add_tag
    remove_tag
    rename
  ].freeze

  class UnsupportedKindError < StandardError; end
  class InvalidPayloadError  < StandardError; end

  class << self
    # Apply the suggestion to its subject and mark it accepted.
    # Wrapped in one transaction so a payload validation failure
    # leaves both the Suggestion and the subject untouched.
    def accept!(suggestion, by_user:)
      raise UnsupportedKindError, "kind=#{suggestion.kind}" unless ITEM_KINDS.include?(suggestion.kind)
      raise InvalidPayloadError, "subject is not an Item" unless suggestion.subject.is_a?(Item)

      Suggestion.transaction do
        apply!(suggestion)
        suggestion.update!(
          status: "accepted",
          resolved_by_user_id: by_user.id,
          resolved_at: Time.current
        )
      end
      suggestion
    end

    def reject!(suggestion, by_user:)
      suggestion.update!(
        status: "rejected",
        resolved_by_user_id: by_user.id,
        resolved_at: Time.current
      )
      suggestion
    end

    private

    def apply!(suggestion)
      item    = suggestion.subject
      payload = suggestion.payload || {}

      case suggestion.kind
      when "add_ingredient"
        ingredient = find_ingredient!(payload)
        ItemIngredient.find_or_create_by!(item: item, ingredient: ingredient) do |row|
          row.confidence = "confirmed"
          row.source     = "human"
        end
      when "remove_ingredient"
        ingredient = find_ingredient!(payload)
        item.item_ingredients.where(ingredient: ingredient).destroy_all
      when "add_tag"
        tag = find_tag!(payload)
        ItemTag.find_or_create_by!(item: item, tag: tag) do |row|
          row.confidence = "confirmed"
          row.source     = "human"
        end
      when "remove_tag"
        tag = find_tag!(payload)
        item.item_tags.where(tag: tag).destroy_all
      when "rename"
        new_name = payload["name"].to_s.strip
        raise InvalidPayloadError, "name required for rename" if new_name.empty?
        item.update!(name: new_name)
      end
    end

    def find_ingredient!(payload)
      slug = payload["ingredient_slug"]
      id   = payload["ingredient_id"]
      ing  = Ingredient.find_by(id: id) if id.present?
      ing ||= Ingredient.find_by(slug: slug) if slug.present?
      raise InvalidPayloadError, "ingredient not found (id=#{id} slug=#{slug})" unless ing
      ing
    end

    def find_tag!(payload)
      slug = payload["tag_slug"]
      id   = payload["tag_id"]
      tag  = Tag.find_by(id: id) if id.present?
      tag ||= Tag.find_by(slug: slug) if slug.present?
      raise InvalidPayloadError, "tag not found (id=#{id} slug=#{slug})" unless tag
      tag
    end
  end
end
