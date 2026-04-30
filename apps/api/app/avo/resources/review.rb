class Avo::Resources::Review < Avo::BaseResource
  # Phase 4.6 — moderation surface. Read-write so a moderator can
  # tweak rating/body if needed; the bulk actions handle the
  # heavy-hand cases (hide / unhide / mark spam).

  self.includes = [:user, :item]
  self.default_view_type = :table

  def fields
    main_panel do
      field :id,         as: :id, only_on: %i[show]
      field :rating,     as: :number
      field :body,       as: :textarea
      field :user,       as: :belongs_to
      field :item,       as: :belongs_to
      field :created_at, as: :date_time, only_on: %i[index show]
    end

    panel "Moderation" do
      field :hidden_at, as: :date_time, only_on: %i[show]
      field :hidden_reason, as: :select, options: Review::HIDDEN_REASONS.index_with(&:itself)
      field :flagged_at, as: :date_time, only_on: %i[show],
            help: "Set automatically by the spam heuristic on save."
    end
  end

  def filters
    filter Avo::Filters::AwaitingModeration
    filter Avo::Filters::ReviewVisibility
  end

  def actions
    action Avo::Actions::Reviews::Hide
    action Avo::Actions::Reviews::MarkSpam
    action Avo::Actions::Reviews::Unhide
  end
end
