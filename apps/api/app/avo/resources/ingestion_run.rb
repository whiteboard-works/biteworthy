class Avo::Resources::IngestionRun < Avo::BaseResource
  # Phase 2.5 — admin can see what the AI extracted, watch state
  # transitions, and re-run a stuck extraction. The actual
  # accept/reject happens at the per-item level (see Avo::Resources::IngestionItem).

  self.includes = [:restaurant, :user]

  def fields
    main_panel do
      field :id,         as: :id
      field :status,     as: :badge, options: {
        info:    %w[queued],
        warning: %w[extracting resolving],
        success: %w[staged published],
        danger:  %w[failed]
      }
      field :input_kind,    as: :badge
      field :restaurant,    as: :belongs_to
      field :user,          as: :belongs_to
      field :source_url,    as: :text, only_on: %i[show]
      field :inputs,        as: :files, hide_on: %i[edit new]
    end

    panel "Pipeline" do
      field :state_history,  as: :code, language: "json", only_on: %i[show]
      field :latency_ms,     as: :number, only_on: %i[show], help: "Wall time of the most recent API call"
      field :failure_message, as: :textarea, only_on: %i[show]
    end

    panel "Cost" do
      field :api_cost_cents,        as: :number, name: "Cost (cents)"
      field :cached_input_tokens,   as: :number
      field :uncached_input_tokens, as: :number
    end

    panel "AI extraction" do
      field :staging,    as: :code, language: "json", hide_on: %i[edit new]
      field :raw_output, as: :code, language: "json", only_on: %i[show],
            help: "Full Anthropic response, kept for debugging"
    end

    field :ingestion_items, as: :has_many
  end

  def actions
    action Avo::Actions::IngestionRuns::ReExtract
  end
end
