FactoryBot.define do
  # Real Colorado mountain-town cities — BiteWorthy's launch market.
  CITY_SAMPLES = [
    { slug: "durango",      name: "Durango",      region: "CO" },
    { slug: "telluride",    name: "Telluride",    region: "CO" },
    { slug: "ouray",        name: "Ouray",        region: "CO" },
    { slug: "silverton",    name: "Silverton",    region: "CO" },
    { slug: "pagosa-springs",name: "Pagosa Springs",region: "CO" },
    { slug: "crested-butte",name: "Crested Butte",region: "CO" },
    { slug: "aspen",        name: "Aspen",        region: "CO" }
  ].freeze

  factory :city do
    transient do
      sequence(:rotation_idx) { |n| n }
    end

    slug   { CITY_SAMPLES[(rotation_idx - 1) % CITY_SAMPLES.size][:slug] }
    name   { (CITY_SAMPLES.find { |s| s[:slug] == slug } || {})[:name]   || slug.tr("-", " ").titleize }
    region { (CITY_SAMPLES.find { |s| s[:slug] == slug } || {})[:region] || "CO" }
    country { "US" }
  end

  # Curated set of real southwest-Colorado restaurants pulled from
  # the 2020 BiteWorthy seeds (`_legacy/db/seeds/*.rb`). Specs that
  # rely on actual menu data become much easier to read with names
  # like "Cream Bean Berry" or "Ninis" instead of "Restaurant 1".
  RESTAURANT_SAMPLES = [
    { slug: "cream-bean-berry", name: "Cream, Bean & Berry" },
    { slug: "ninis",            name: "Ninis Taqueria" },
    { slug: "rgps",             name: "RGPs" },
    { slug: "home-slice",       name: "Home Slice Pizza" },
    { slug: "oscars",           name: "Oscar's Cafe" },
    { slug: "thai-kitchen",     name: "Thai Kitchen" },
    { slug: "sizzling-siam",    name: "Sizzling Siam" },
    { slug: "himalayan",        name: "Himalayan Kitchen" },
    { slug: "dsp",              name: "Durango Smelter Pub" }
  ].freeze

  factory :restaurant do
    transient do
      sequence(:rotation_idx) { |n| n }
    end

    city
    slug { "#{RESTAURANT_SAMPLES[(rotation_idx - 1) % RESTAURANT_SAMPLES.size][:slug]}-#{rotation_idx}" }
    name do
      base = RESTAURANT_SAMPLES.find { |s| slug.start_with?(s[:slug]) } ||
             RESTAURANT_SAMPLES[(rotation_idx - 1) % RESTAURANT_SAMPLES.size]
      base[:name]
    end
    status { "draft" }

    trait :published do
      status { "published" }
    end
  end
end
