# frozen_string_literal: true

# Renders the Ingredient and Tag catalogs into compact text formats
# the Anthropic prompt-cache can hold. Both catalogs hover around 1k
# rows; the rendered text is the bulk of the input tokens, so caching
# is the difference between a $0.001 menu and a $0.05 menu.
#
# Format:
#
#   slug | name | (path) | aliases
#
#   meat-beef | Beef | meat.beef | steak
#   dairy-cheese | Cheese | dairy.cheese | fromage, queso
#   ...
#
# A reader who's not seen the format can infer it from the first row;
# the LLM does the same.
module Ingestion
  module CatalogBuilder
    HEADER = "# slug | name | (path) | aliases"

    class << self
      def ingredients_text
        rows = Ingredient.order(:path).pluck(:slug, :name, :path, :aliases)
        format_rows(rows)
      end

      def tags_text
        # Tags share the same shape with one extra useful field
        # (family) — but we keep the output schema identical to
        # ingredients to keep the prompt format uniform.
        rows = Tag.order(:family, :path).pluck(:slug, :name, :path, :family).map do |slug, name, path, family|
          [slug, name, "#{family}.#{path}", []]
        end
        format_rows(rows)
      end

      private

      def format_rows(rows)
        ([HEADER] + rows.map { |slug, name, path, aliases|
          aliases_str = Array(aliases).reject(&:blank?).join(", ")
          "#{slug} | #{name} | #{path} | #{aliases_str}"
        }).join("\n")
      end
    end
  end
end
