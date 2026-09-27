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
        raise ArgumentError, "name required" if clean_name.parameterize.blank?

        state = state_name(region)
        raise ArgumentError, "region must be a US state, e.g. 'Utah' or 'UT'" if state.nil?

        # Check-then-insert, so two overlapping requests could both pass the
        # check; a transaction-scoped advisory lock makes them take turns.
        City.transaction do
          City.connection.execute("SELECT pg_advisory_xact_lock(hashtext('cities_create'))")
          # Cities are few enough to compare in Ruby; see same_name?.
          base = clean_name.parameterize
          same_name = City.order(:created_at).select { |c| same_name?(c.name, clean_name) }
          # Older rows may hold a code ("CO", from the Durango seed task) or
          # stray whitespace, so compare normalized states.
          in_state = same_name.select { |c| state_name(c.region) == state }
          # "SC" could be Santa Clara or Santa Cruz; picking one would file
          # restaurants under the wrong city.
          if in_state.size > 1
            raise ArgumentError, "'#{clean_name}' could be #{in_state.map(&:name).join(' or ')}; use the full name"
          end
          raise Duplicate, in_state.first if in_state.any?

          # A same-named row whose state can't be read might be this city or
          # another state's; guessing either way is wrong, so make someone say.
          if (unknown = same_name.find { |c| state_name(c.region).nil? })
            raise ArgumentError, "'#{unknown.name}' (#{unknown.slug}) is on file with no state; set its state first"
          end

          City.create!(name: clean_name, slug: unique_slug(base, state), region: state, country: "US")
        end
      end

      # Springfield, IL and Springfield, MO are different cities; the second
      # one to arrive gets its state in the slug, then a number if needed.
      def unique_slug(base, state)
        return base unless City.exists?(slug: base)

        with_state = "#{base}-#{state.parameterize}"
        return with_state unless City.exists?(slug: with_state)

        n = 2
        n += 1 while City.exists?(slug: "#{with_state}-#{n}")
        "#{with_state}-#{n}"
      end

      # Punctuation, civic abbreviations, and initials ("SLC" for Salt
      # Lake City, either way round) all name the same city.
      def same_name?(a, b)
        name_key(a) == name_key(b) || initials(a) == compact(b) || initials(b) == compact(a)
      end

      # "Ft. Worth" and "Fort Worth", "St. Louis" and "Saint Louis": the
      # civic abbreviations people actually type, expanded before comparing.
      WORD_ABBREVIATIONS = { "ft" => "fort", "st" => "saint", "mt" => "mount", "pt" => "point" }.freeze

      def name_key(name)
        name.parameterize.split("-").map { |w| WORD_ABBREVIATIONS.fetch(w, w) }.join("-")
      end

      def initials(name) = name.split(/[^[:alnum:]]+/).reject(&:empty?).map { |w| w[0] }.join.downcase
      def compact(name) = name.gsub(/[^[:alnum:]]/, "").downcase

      def state_name(region)
        value = region.to_s.strip
        US_STATES[value.upcase] || US_STATES.values.find { |n| n.casecmp?(value) }
      end
    end
  end
end
