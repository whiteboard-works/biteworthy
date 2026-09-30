# frozen_string_literal: true

module Tools
  module Profile
    # The city the caller is usually in. Coarse on purpose — a slug from
    # `list_cities`, never coordinates — and a default, not a filter:
    # `search_restaurants` falls back to it for a listing with no city
    # named, while a search by name still looks everywhere.
    class SetHomeCity < Tools::Base
      audience :user

      tool_name "set_home_city"
      title "Set home city"
      description <<~TEXT
        Remember which city the caller is usually in, so "what's nearby" and
        "where can I eat" can be answered without asking which city first.
        `search_restaurants` uses it whenever `city_slug` is omitted on a
        listing or a diet ranking; a search by name is never limited to it.

        Take the slug from `list_cities`. Do not guess a city from a name or
        an accent — ask, or read it from the page context. Say what changed.
        Pass an empty string to clear it, the same as the settings page.
      TEXT

      input_schema(
        properties: {
          city_slug: {
            type: "string",
            description: 'City slug from list_cities, e.g. "durango". Empty string clears the home city.'
          }
        },
        required: [ "city_slug" ]
      )

      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

      running_description do |args|
        args[:city_slug].present? ? "Setting your home city to #{args[:city_slug]}" : "Clearing your home city"
      end

      def self.perform(context:, city_slug:)
        city = nil
        if city_slug.present?
          city = City.find_by(slug: city_slug.to_s)
          raise Errors::NotFound, "No city with slug #{city_slug.inspect}. Try list_cities." if city.nil?
        end

        profile  = context.user!.profile
        previous = profile.home_city&.slug
        # Locked like the REST path, which may be writing the same row.
        profile.with_lock { profile.update!(home_city: city) }

        ok(previous_home_city: previous, home_city: city&.summary&.slice(:slug, :name, :region))
      end
    end
  end
end
