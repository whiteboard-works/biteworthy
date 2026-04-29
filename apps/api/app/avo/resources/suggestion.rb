class Avo::Resources::Suggestion < Avo::BaseResource
  # Phase-1.md §1.5 calls for Suggestion to be read-only — Phase 4
  # adds the moderator-action workflow. Same trust-based gating as
  # User for now.

  def fields
    field :id,                  as: :id
    field :kind,                as: :text
    field :status,              as: :text
    field :payload,             as: :code, language: "json"
    field :resolved_at,         as: :date_time
    field :created_at,          as: :date_time
    field :updated_at,          as: :date_time

    field :user,             as: :belongs_to
    field :resolved_by_user, as: :belongs_to
    field :subject,
          as: :belongs_to,
          polymorphic_as: :subject,
          types: [Restaurant, Item, Ingredient, Tag]
  end
end
