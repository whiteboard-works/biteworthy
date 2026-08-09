# frozen_string_literal: true

module Tools
  # The catalog. `for(context)` is the only supported way to get a tool
  # list — it filters by audience, so an anonymous caller never sees a
  # tool that would just 401, and a non-admin never learns that the admin
  # tools exist.
  module Registry
    # Grouped by domain. The order within each is roughly the order a
    # conversation uses them, which is also the order they read best in a
    # `tools/list` dump.
    DOMAINS = {
      meta: [
        "Meta::DescribeCapabilities"
      ],
      discovery: [
        "Discovery::SearchRestaurants",
        "Discovery::GetRestaurant",
        "Discovery::GetMenu",
        "Discovery::ExplainItem",
        "Discovery::SearchTaxonomy"
      ],
      profile: [
        "Profile::GetProfile",
        "Profile::UpdateAvoidLists",
        "Profile::SetStrictness",
        "Profile::SaveRestaurant",
        "Profile::SaveItem"
      ],
      ingestion: [
        "Ingestion::StartMenuScan",
        "Ingestion::GetScanStatus",
        "Ingestion::ListStagedItems",
        "Ingestion::EditStagedItem",
        "Ingestion::AcceptStagedItems",
        "Ingestion::RejectStagedItems",
        "Ingestion::UndoStagedItem"
      ],
      reviews: [
        "Reviews::ListReviews",
        "Reviews::WriteReview",
        "Reviews::EditReview",
        "Reviews::DeleteReview",
        "Reviews::ReportReview"
      ],
      suggestions: [
        "Suggestions::SuggestCorrection",
        "Suggestions::ListSuggestions",
        "Suggestions::ResolveSuggestion"
      ],
      claims: [
        "Claims::ClaimRestaurant",
        "Claims::VerifyClaim"
      ],
      history: [
        "History::ListVisits",
        "History::ListSaved"
      ],
      restaurants: [
        "Restaurants::CreateRestaurant",
        "Restaurants::EditRestaurant",
        "Restaurants::ConfirmRestaurantData"
      ],
      structure: [
        "Structure::GetMenuStructure",
        "Structure::EditMenuStructure",
        "Structure::EditPlace"
      ],
      items: [
        "Items::EditItem"
      ],
      taxonomy: [
        "Taxonomy::CreateTaxonomyNode",
        "Taxonomy::EditTaxonomyNode",
        "Taxonomy::DeleteTaxonomyNode"
      ],
      moderation: [
        "Moderation::ListModerationQueue",
        "Moderation::ModerateReview"
      ],
      users: [
        "Users::ListUsers",
        "Users::SetUserRole"
      ]
    }.freeze

    class << self
      def all
        @all ||= DOMAINS.values.flatten.map { |name| Tools.const_get(name) }.freeze
      end

      def domain_of(tool)
        DOMAINS.find { |_name, tools| tools.include?(tool.name.delete_prefix("Tools::")) }&.first
      end

      # Both filters, not just audience. A read-only credential that is
      # *shown* the write tools will have a model pick one, fail, and
      # spend a turn learning what the list could have told it — and with
      # deferred loading it pays for the schemas too. `enforce_scope!` in
      # `Tools::Base` is still the boundary; this keeps the catalogue
      # honest about what the caller can actually do.
      def for(context)
        all.select { |tool| visible_to?(tool, context) && permitted_by_scope?(tool, context) }
      end

      def find(name)
        all.find { |tool| tool.name_value == name }
      end

      private

      def permitted_by_scope?(tool, context)
        Scopes.satisfied?(context.scopes, Scopes.for_tool(tool))
      end

      def visible_to?(tool, context)
        case tool.audience
        when :public then true
        when :user   then context.signed_in?
        when :admin  then context.admin?
        else false
        end
      end
    end
  end
end
