# frozen_string_literal: true

# Adding a city Biteworthy covers. Shared by the admin REST endpoint and
# the `create_city` tool so the slug rule and the duplicate check live in
# one place — a second "salt-lake-city" beside "slc" would split a city's
# restaurants across two pages.
module Cities
  class Create
    class Duplicate < StandardError
      attr_reader :city

      def initialize(city)
        @city = city
        super("#{city.name}, #{city.region} already exists as '#{city.slug}'")
      end
    end

    class << self
      def call(name:, region:, country: "US", latitude: nil, longitude: nil)
        clean_name   = name.to_s.strip
        clean_region = region.to_s.strip.upcase
        raise ArgumentError, "name required" if clean_name.blank?
        raise ArgumentError, "region required (two-letter state code, e.g. 'UT')" unless clean_region.match?(/\A[A-Z]{2}\z/)

        existing = City.where("lower(name) = ?", clean_name.downcase).find_by(region: clean_region)
        raise Duplicate, existing if existing

        # Springfield, IL and Springfield, MO are different cities; the
        # second one to arrive gets its state in the slug.
        slug = clean_name.parameterize
        slug = "#{slug}-#{clean_region.downcase}" if City.exists?(slug: slug)

        City.create!(
          name: clean_name, slug: slug, region: clean_region,
          country: country.to_s.strip.upcase.presence || "US",
          latitude: latitude, longitude: longitude
        )
      end
    end
  end
end
