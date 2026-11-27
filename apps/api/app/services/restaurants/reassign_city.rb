# frozen_string_literal: true

# Move a restaurant to another city. Shared by the admin PATCH and the
# MCP admin tools so a `city: "Draper"` cannot silently rewrite address
# text while leaving `restaurants.city_id` (and the public URL) behind.
#
# The restaurant slug is the public lookup key — it does not change.
# The destination must already exist in the same state and country;
# inventing a city here would split a restaurant onto a page nobody
# seeded.
module Restaurants
  class ReassignCity
    class UnknownCity < StandardError; end

    class RegionMismatch < StandardError
      attr_reader :current_city, :target_city

      def initialize(current_city, target_city)
        @current_city = current_city
        @target_city  = target_city
        super(
          "#{target_city.name} is in #{place_label(target_city)}; " \
          "this restaurant is in #{place_label(current_city)}. " \
          "Move only within the same state and country."
        )
      end

      def self.place_label(city)
        region = Cities::Create.state_name(city.region) || city.region
        "#{region}, #{city.country}"
      end

      def place_label(city) = self.class.place_label(city)
    end

    class << self
      def call(restaurant:, city:)
        target = find_city!(city)
        return restaurant if restaurant.city_id == target.id

        assert_same_region!(restaurant.city, target)
        restaurant.update!(city: target)
        sync_address!(restaurant, target)
        restaurant.reload
      end

      private

      def find_city!(value)
        text = value.to_s.strip
        raise UnknownCity, unknown_message(value) if text.blank? || !scalar?(value)

        record = if text.match?(Restaurant::UUID_FORMAT)
          City.find_by(id: text)
        else
          City.find_by(slug: text) || City.find_by(slug: text.parameterize)
        end
        raise UnknownCity, unknown_message(value) if record.nil?

        record
      end

      def scalar?(value)
        value.is_a?(String) || value.is_a?(Numeric)
      end

      def unknown_message(value)
        "No city matches #{value.to_s.inspect} (use a city slug or id)."
      end

      def assert_same_region!(current, target)
        return if same_place?(current, target)

        raise RegionMismatch.new(current, target)
      end

      def same_place?(left, right)
        left_region  = region_key(left)
        right_region = region_key(right)
        return false if left_region.blank? || right_region.blank?

        country_key(left) == country_key(right) && left_region == right_region
      end

      def country_key(city) = city.country.to_s.strip.upcase

      def region_key(city)
        Cities::Create.state_name(city.region) || city.region.to_s.strip.downcase.presence
      end

      def sync_address!(restaurant, city)
        address = restaurant.addresses.order(:created_at).first
        return unless address

        # City text follows the City row. Coordinates, postal code, and
        # the map place id still describe the old pin — SearchRestaurants
        # ranks by those — so they go until a later address write.
        address.update!(
          city: city.name, region: city.region, country: city.country,
          postal_code: nil, latitude: nil, longitude: nil, map_provider_place_id: nil
        )
      end
    end
  end
end
