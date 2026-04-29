class Avo::Resources::IngestionItem < Avo::BaseResource
  # Phase 2.5 — admin verification surface. Each row shows the AI's
  # extracted item alongside the resolved ingredient + tag slugs;
  # Accept calls IngestionItem#promote! (added in Phase 2.2), which
  # materializes a real Item + ItemIngredient + ItemTag rows.

  self.includes = [:ingestion_run, :item]

  def fields
    main_panel do
      field :id,          as: :id
      field :name,        as: :text
      field :description, as: :textarea
      field :section_name, as: :text, name: "Section"
      field :decision, as: :badge, options: {
        info:    %w[pending edited],
        success: %w[accepted],
        danger:  %w[rejected]
      }
      field :decided_at, as: :date_time, only_on: %i[show]
      field :ingestion_run, as: :belongs_to
      field :item,          as: :belongs_to, help: "Set after promote!"
    end

    panel "AI suggestions" do
      field :ingredients_payload, as: :code, language: "json", name: "Ingredients (slug + confidence)"
      field :tags_payload,        as: :code, language: "json", name: "Tags (slug + confidence)"
      field :prices_payload,      as: :code, language: "json", name: "Prices (size + cents)"
    end

    panel "Couldn't match" do
      field :unresolved_ingredients, as: :code, language: "json"
      field :unresolved_tags,         as: :code, language: "json"
    end
  end

  def actions
    action Avo::Actions::IngestionItems::Accept
    action Avo::Actions::IngestionItems::Reject
  end
end
