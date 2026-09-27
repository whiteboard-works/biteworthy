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

    # Full names are what `cities.region` holds (Durango's is "Colorado")
    # and what the location URLs are built from, so a typo here would be
    # permanent in every restaurant URL in the city. Codes are accepted as
    # input and stored as the name.
    US_STATES = {
      "AL" => "Alabama", "AK" => "Alaska", "AZ" => "Arizona", "AR" => "Arkansas",
      "CA" => "California", "CO" => "Colorado", "CT" => "Connecticut", "DE" => "Delaware",
      "DC" => "District of Columbia", "FL" => "Florida", "GA" => "Georgia", "HI" => "Hawaii",
      "ID" => "Idaho", "IL" => "Illinois", "IN" => "Indiana", "IA" => "Iowa",
      "KS" => "Kansas", "KY" => "Kentucky", "LA" => "Louisiana", "ME" => "Maine",
      "MD" => "Maryland", "MA" => "Massachusetts", "MI" => "Michigan", "MN" => "Minnesota",
      "MS" => "Mississippi", "MO" => "Missouri", "MT" => "Montana", "NE" => "Nebraska",
      "NV" => "Nevada", "NH" => "New Hampshire", "NJ" => "New Jersey", "NM" => "New Mexico",
      "NY" => "New York", "NC" => "North Carolina", "ND" => "North Dakota", "OH" => "Ohio",
      "OK" => "Oklahoma", "OR" => "Oregon", "PA" => "Pennsylvania", "RI" => "Rhode Island",
      "SC" => "South Carolina", "SD" => "South Dakota", "TN" => "Tennessee", "TX" => "Texas",
      "UT" => "Utah", "VT" => "Vermont", "VA" => "Virginia", "WA" => "Washington",
      "WV" => "West Virginia", "WI" => "Wisconsin", "WY" => "Wyoming"
    }.freeze

    class << self
      def call(name:, region:)
        clean_name = name.to_s.strip
        raise ArgumentError, "name required" if clean_name.blank?

        state = state_name(region)
        raise ArgumentError, "region must be a US state, e.g. 'Utah' or 'UT'" if state.nil?

        existing = City.where("lower(name) = ?", clean_name.downcase).find_by(region: state)
        raise Duplicate, existing if existing

        # Springfield, IL and Springfield, MO are different cities; the
        # second one to arrive gets its state in the slug.
        slug = clean_name.parameterize
        slug = "#{slug}-#{state.parameterize}" if City.exists?(slug: slug)

        City.create!(name: clean_name, slug: slug, region: state, country: "US")
      end

      def state_name(region)
        value = region.to_s.strip
        US_STATES[value.upcase] || US_STATES.values.find { |n| n.casecmp?(value) }
      end
    end
  end
end
