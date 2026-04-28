json.array!(@restaurants) do |restaurant|
  json.extract! restaurant, :id, :name, :slogan, :latitude, :longitude
  json.url restaurant_url(restaurant, format: :json)
end
