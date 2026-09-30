# frozen_string_literal: true

module Geo
  EARTH_RADIUS_KM = 6371.0

  # Great-circle distance. Plenty for "which of these is closer" at town
  # scale; not a routing distance.
  def self.distance_km(lat1, lng1, lat2, lng2)
    rad  = Math::PI / 180
    dlat = (lat2.to_f - lat1.to_f) * rad
    dlng = (lng2.to_f - lng1.to_f) * rad
    a = Math.sin(dlat / 2)**2 +
        Math.cos(lat1.to_f * rad) * Math.cos(lat2.to_f * rad) * Math.sin(dlng / 2)**2
    2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a))
  end
end
