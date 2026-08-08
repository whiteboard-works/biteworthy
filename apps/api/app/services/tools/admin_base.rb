# frozen_string_literal: true

module Tools
  # Base for every tool that writes to data other people depend on.
  #
  # Admin tools edit live menus, the taxonomy the filter reads, and who
  # else is an admin. `Registry.for(context)` drops them entirely for
  # non-admins, so a normal caller's `tools/list` never mentions them —
  # the audience declared here is what that filter reads, and it is
  # inherited down the whole subtree.
  class AdminBase < Tools::Base
    audience :admin

    class << self
      def find_restaurant!(reference)
        Restaurant.find_by_id_or_slug!(reference)
      end

      # Admin surfaces show drafts and removed dishes, so this is the
      # one place that does NOT scope to published.
      def restaurant_row(restaurant)
        {
          id:     restaurant.id,
          slug:   restaurant.slug,
          name:   restaurant.name,
          status: restaurant.status
        }
      end
    end
  end
end
