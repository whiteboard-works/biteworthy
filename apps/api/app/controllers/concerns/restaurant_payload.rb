# Shared restaurant serialization — the public detail and list rows
# (RestaurantsController) and the branding door, which answers with the
# same detail row so the page re-renders from the response.
module RestaurantPayload
  extend ActiveSupport::Concern

  private

  # Lighter than #restaurant_payload — list rows don't need claim
  # fields, but the home screen wants an address line + coords (the
  # near-me sort lands with expo-location in a followup). Hours are
  # included so cards can show open/closed badges; `logo_url` so they
  # can show the logo.
  def restaurant_summary_payload(r)
    first_address = r.addresses.first
    {
      id:     r.id,
      slug:   r.slug,
      name:   r.name,
      status: r.status,
      web_path: r.web_path,
      city:   { slug: r.city.slug, name: r.city.name, region: r.city.region },
      # Keep the original street/coords fields — the OpenAPI contract and
      # web RestaurantSummary still read them — and add the full address
      # object so admin/MCP callers can see city/region/postal/country.
      street:    first_address&.street,
      address:   address_payload(first_address),
      latitude:  first_address&.latitude&.to_f,
      longitude: first_address&.longitude&.to_f,
      time_zone: r.city.time_zone,
      hours:     hours_payload(r),
      logo_url:  representation_url_for(r.logo, :thumb)
    }
  end

  def restaurant_payload(r)
    first_address = r.addresses.first
    {
      id:                 r.id,
      slug:               r.slug,
      name:               r.name,
      about:              r.about,
      phone:              r.phone,
      website:            r.website,
      status:             r.status,
      web_path:           r.web_path,
      # Phase 4.9 — non-PII signals so the web page can show or
      # hide the "Claim this restaurant" button without a second
      # roundtrip. claimed_by_user_id is the user's UUID; not
      # private and useful for "is this me" comparisons.
      claimed_at:         r.claimed_at,
      claimed_by_user_id: r.claimed_by_user_id,
      city: {
        id:     r.city.id,
        slug:   r.city.slug,
        name:   r.city.name,
        region: r.city.region
      },
      address: address_payload(first_address),
      # Restaurant hours (sorted by day_of_week, then opens_at) and timezone
      # for computing open/closed status. Multiple intervals per day support
      # split shifts (lunch 11-14, dinner 17-21). Null opens_at/closes_at
      # means closed that day.
      time_zone: r.city.time_zone,
      hours:     hours_payload(r),
      # Owner branding (Restaurants::Branding). Variant URLs, never the
      # original upload; nil when nothing is attached.
      logo_url:   representation_url_for(r.logo, :thumb),
      banner_url: representation_url_for(r.banner, :card)
    }
  end

  def address_payload(address)
    address && {
      street:      address.street,
      city:        address.city,
      region:      address.region,
      postal_code: address.postal_code,
      country:     address.country
    }
  end

  def hours_payload(r)
    r.hours.map { |h|
      {
        day_of_week: h.day_of_week,
        opens_at:    h.opens_at&.strftime("%H:%M"),
        closes_at:   h.closes_at&.strftime("%H:%M")
      }
    }
  end
end
