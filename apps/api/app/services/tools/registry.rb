# frozen_string_literal: true

module Tools
  # The catalog. `for(context)` is the only supported way to get a tool
  # list — it filters by audience, so an anonymous caller never sees a
  # tool that would just 401, and a non-admin never learns that the admin
  # tools exist.
  module Registry
    class << self
      # Ordered roughly by how a conversation uses them: find a place,
      # read its menu, then act.
      def all
        @all ||= [
          Discovery::SearchRestaurants,
          Discovery::GetRestaurant,
          Discovery::GetMenu,
          Discovery::ExplainItem,
          Discovery::SearchTaxonomy,
          Profile::GetProfile,
          Profile::UpdateAvoidLists,
          Profile::SetStrictness,
          Profile::SaveRestaurant,
          Profile::SaveItem
        ].freeze
      end

      def for(context)
        all.select { |tool| visible_to?(tool, context) }
      end

      def find(name)
        all.find { |tool| tool.name_value == name }
      end

      private

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
