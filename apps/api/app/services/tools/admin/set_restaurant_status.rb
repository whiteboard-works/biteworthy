# frozen_string_literal: true

module Tools
  module Admin
    # Change a restaurant's status: draft, published, or closed. Archive and
    # restore go through the existing REST endpoints (soft/hard delete).
    class SetRestaurantStatus < Tools::AdminBase
      tool_name "set_restaurant_status"
      title "Set restaurant status"
      description <<~TEXT
        Change a restaurant's status to draft, published, or closed.

        draft = not in search results, not on city page. Regular state for a
        new restaurant being built up.

        published = live, in search, on city page. Requires enough verified
        menu content (auto-publishes at 80% threshold).

        closed = was published, now marked closed. Still in database, grayed
        out in lists.

        Archive and restore are separate operations (soft/hard delete in the
        REST API) and are not handled here.
      TEXT

      input_schema(
        properties: {
          restaurant: {
            type: "string",
            description: "Restaurant UUID or slug."
          },
          status: {
            type: "string",
            description: "New status: #{Restaurant::STATUSES.join(', ')}."
          }
        },
        required: %w[restaurant status]
      )

      annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)
      unrecoverable_when { false }

      running_description { |args| "Setting status to #{args[:status]}" }

      def self.perform(context:, restaurant:, status:)
        context.admin!
        record = find_restaurant!(restaurant)

        unless Restaurant::STATUSES.include?(status.to_s)
          raise Errors::InvalidArgument, "Invalid status. Allowed: #{Restaurant::STATUSES.join(', ')}"
        end

        record.update!(status: status)

        ok(
          restaurant_id: record.id,
          slug: record.slug,
          name: record.name,
          status: record.status
        )
      end
    end
  end
end
